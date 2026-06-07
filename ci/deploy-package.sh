#!/bin/bash
# Deploy a single package to remote server via SCP with atomic flock-based DB update.
# Runs inside the Arch Linux container.
set -euo pipefail

PKGDIR="$1"
SSH_HOST="${SSH_HOST:-dryam.ru}"
SSH_PORT="${SSH_PORT:-222}"
SSH_USER="${SSH_USER:-root}"
REPO_PATH="${REPO_PATH:-/tmp/mnt/e73e95d7-6854-49b0-8a0a-b0a8923ad782/aarch64}"
STAGING="/tmp/pkgs-staging"
LOCKFILE="/tmp/repo.lock"

SSH_KEY="${SSH_KEY:-/tmp/ssh_key}"
if [ -z "${SSH_KEY:-}" ] || [ ! -f "$SSH_KEY" ]; then
	echo "ERROR: SSH_KEY not set or key file not found"
	exit 1
fi
chmod 600 "$SSH_KEY"

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o Port=$SSH_PORT"
SCP_OPTS="-O $SSH_OPTS"
REMOTE="$SSH_USER@$SSH_HOST"

cd /workspace

# Find package file
PKGFILE=$(find "$PKGDIR" -maxdepth 1 -name '*.pkg.tar.*' -type f 2>/dev/null | head -1)
echo "DEBUG: PKGDIR=$PKGDIR"
echo "DEBUG: find output: $PKGFILE"
echo "DEBUG: ls -la $PKGDIR:"
ls -la "$PKGDIR" 2>/dev/null || echo "(cannot list $PKGDIR)"

if [ -z "$PKGFILE" ] || [ ! -f "$PKGFILE" ]; then
	echo "ERROR: No package file found in $PKGDIR"
	exit 1
fi

PKGNAME=$(basename "$PKGFILE")
PKGSIZE=$(stat -c%s "$PKGFILE" 2>/dev/null || echo "unknown")
echo "=== Deploying $PKGNAME ($PKGSIZE bytes) ==="

for attempt in $(seq 1 10); do
	echo "=== Deploy attempt $attempt/10 ==="

	WORKDIR=$(mktemp -d /tmp/repo-work-XXXXXX)

	# Ensure staging and repo dirs exist on remote
	ssh $SSH_OPTS "$REMOTE" "mkdir -p $STAGING $REPO_PATH" || {
		echo "SSH connection failed, retrying..."
		sleep 3
		rm -rf "$WORKDIR"
		continue
	}

	# ── 1. SCP new package to staging ──
	echo "scp: $PKGFILE ($(stat -c%s "$PKGFILE") bytes)"
	if ! scp $SCP_OPTS "$PKGFILE" "$REMOTE:$STAGING/" 2>&1; then
		echo "SCP failed (exit=$?), retrying..."
		sleep 3
		rm -rf "$WORKDIR"
		continue
	fi

	# ── 2. Download current repo DB (with flock for consistency) ──
	DB_EXISTS=$(
		ssh $SSH_OPTS "$REMOTE" "flock -w 30 $LOCKFILE -c \"
      if [ -f $REPO_PATH/repo.db.tar.gz ]; then
        cp $REPO_PATH/repo.db.tar.gz $STAGING/db_current.tar.gz
        echo YES
      else
        echo NO
      fi
    \""
	) || {
		echo "Failed to check repo DB, retrying..."
		sleep 3
		rm -rf "$WORKDIR"
		continue
	}

	if [ "$DB_EXISTS" = "YES" ]; then
		scp $SCP_OPTS "$REMOTE:$STAGING/db_current.tar.gz" "$WORKDIR/repo.db.tar.gz" || {
			echo "Failed to download repo DB, retrying..."
			sleep 3
			rm -rf "$WORKDIR"
			continue
		}
		DB_MD5=$(md5sum "$WORKDIR/repo.db.tar.gz" | cut -d' ' -f1)
		scp $SCP_OPTS "$WORKDIR/repo.db.tar.gz" "$REMOTE:$STAGING/db_current.tar.gz" 2>/dev/null || true
		cp "$PKGFILE" "$WORKDIR/"
		(cd "$WORKDIR" && repo-add -R repo.db.tar.gz "$PKGNAME" 2>/dev/null) || true
	else
		cd "$WORKDIR"
		cp "$PKGFILE" "$WORKDIR/"
		repo-add repo.db.tar.gz "$PKGNAME" 2>/dev/null || true
		cd /workspace
		DB_MD5="__first_deploy__"
	fi

	# ── 3. Generate index.html ──
	REMOTE_LIST=$(ssh $SSH_OPTS "$REMOTE" "ls $REPO_PATH/*.pkg.tar.* 2>/dev/null" || true)
	{
		printf '<!DOCTYPE html>\n<html lang="en">\n<head><meta charset="UTF-8"><title>aarch64 Repository</title></head>\n<body>\n'
		printf '<h1>Arch Linux aarch64 Package Repository</h1>\n<p>Optimized for Raspberry Pi 5 (Cortex-A76)</p>\n<hr>\n<pre>\n'
		printf '%s\n' "$REMOTE_LIST" | while IFS= read -r f; do
			[ -z "$f" ] && continue
			n=$(basename "$f")
			ne=$(printf '%s\n' "$n" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
			printf '<a href="aarch64/%s">%s</a>\n' "$n" "$ne"
		done
		ne=$(printf '%s\n' "$PKGNAME" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
		printf '<a href="aarch64/%s">%s</a>\n' "$PKGNAME" "$ne"
		printf '</pre>\n</body>\n</html>\n'
	} >"$WORKDIR/index.html"

	# ── 4. SCP updated files to staging ──
	scp $SCP_OPTS "$WORKDIR/repo.db.tar.gz" "$REMOTE:$STAGING/db_new.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/repo.db.tar.gz.old" "$REMOTE:$STAGING/db_old.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/repo.files.tar.gz" "$REMOTE:$STAGING/db_files.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/repo.files.tar.gz.old" "$REMOTE:$STAGING/db_files_old.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/index.html" "$REMOTE:$STAGING/" 2>/dev/null || true

	# ── 5. Atomic deploy with flock + conflict detection ──
	DEPLOY_RESULT=$(
		ssh $SSH_OPTS "$REMOTE" bash -s -- "$REPO_PATH" "$STAGING" "$LOCKFILE" "$DB_MD5" <<'SSH_SCRIPT'
set -euo pipefail
REPO_PATH="$1"
STAGING="$2"
LOCKFILE="$3"
EXPECTED_MD5="$4"

(
  if ! flock -w 120 200; then
    echo "LOCK_TIMEOUT"
    exit 0
  fi

  if [ "$EXPECTED_MD5" != "__first_deploy__" ] && [ -f "$STAGING/db_current.tar.gz" ]; then
    CURRENT_MD5=$(md5sum "$REPO_PATH/repo.db.tar.gz" 2>/dev/null | cut -d' ' -f1 || echo "none")
    STAGED_MD5=$(md5sum "$STAGING/db_current.tar.gz" | cut -d' ' -f1)
    if [ "$CURRENT_MD5" != "$STAGED_MD5" ]; then
      echo "CONFLICT"
      exit 0
    fi
  fi

  mv "$STAGING"/*.pkg.tar.* "$REPO_PATH/" 2>/dev/null || true
  mv "$STAGING"/db_new.tar.gz       "$REPO_PATH/repo.db.tar.gz"
  mv "$STAGING"/db_old.tar.gz       "$REPO_PATH/repo.db.tar.gz.old"  2>/dev/null || true
  mv "$STAGING"/db_files.tar.gz     "$REPO_PATH/repo.files.tar.gz"   2>/dev/null || true
  mv "$STAGING"/db_files_old.tar.gz "$REPO_PATH/repo.files.tar.gz.old" 2>/dev/null || true
  mv "$STAGING"/index.html          "$REPO_PATH/../index.html"        2>/dev/null || true

  rm -f "$STAGING"/db_current.tar.gz "$STAGING"/db_new.tar.gz \
        "$STAGING"/db_old.tar.gz "$STAGING"/db_files.tar.gz \
        "$STAGING"/db_files_old.tar.gz
  echo "DEPLOY_OK"
) 200>"$LOCKFILE"
SSH_SCRIPT
	)

	rm -rf "$WORKDIR"

	if echo "$DEPLOY_RESULT" | grep -q "DEPLOY_OK"; then
		echo "=== Deploy successful ==="
		rm -f "$SSH_KEY"
		exit 0
	elif echo "$DEPLOY_RESULT" | grep -q "CONFLICT"; then
		echo "DB was modified by another job, retrying..."
		sleep 3
	else
		echo "Deploy issue ($DEPLOY_RESULT), retrying..."
		sleep 3
	fi
done

echo "ERROR: Deploy failed after 10 attempts"
exit 1
