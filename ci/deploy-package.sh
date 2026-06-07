#!/bin/bash
set -euo pipefail

PKGDIR="$1"
SSH_HOST="${SSH_HOST:?ERROR: SSH_HOST not set}"
SSH_PORT="${SSH_PORT:?ERROR: SSH_PORT not set}"
SSH_USER="${SSH_USER:?ERROR: SSH_USER not set}"
REPO_PATH="${REPO_PATH:?ERROR: REPO_PATH not set}"
STAGING_BASE="/tmp/pkgs-staging"
LOCKFILE="/tmp/repo.lock"

SSH_KEY="${SSH_KEY:-/tmp/ssh_key}"
if [ -z "${SSH_KEY:-}" ] || [ ! -f "$SSH_KEY" ]; then
	echo "ERROR: SSH_KEY not set or key file not found"
	exit 1
fi
chmod 600 "$SSH_KEY"

SSH_OPTS="-i $SSH_KEY -o ConnectTimeout=10 -o Port=$SSH_PORT"
SCP_OPTS="-O $SSH_OPTS"
REMOTE="$SSH_USER@$SSH_HOST"

cd /workspace

PKGFILE=$(find "$PKGDIR" -maxdepth 1 -name '*.pkg.tar.*' -type f 2>/dev/null | head -1)
if [ -n "$PKGFILE" ]; then
	PKGFILE="/workspace/$PKGFILE"
fi
if [ -z "$PKGFILE" ] || [ ! -f "$PKGFILE" ]; then
	echo "ERROR: No package file found in $PKGDIR"
	exit 1
fi
PKGNAME=$(basename "$PKGFILE")
STAGING="$STAGING_BASE/$PKGNAME-deploy"

echo "=== Deploying $PKGNAME ==="

for attempt in $(seq 1 10); do
	echo "=== Deploy attempt $attempt/10 ==="

	WORKDIR=$(mktemp -d /tmp/repo-work-XXXXXX)

	ssh $SSH_OPTS "$REMOTE" "mkdir -p $STAGING $REPO_PATH" || {
		echo "SSH connection failed, retrying..."
		sleep 3
		rm -rf "$WORKDIR"
		continue
	}

	if ! scp $SCP_OPTS "$PKGFILE" "$REMOTE:$STAGING/" 2>&1; then
		echo "SCP package failed, retrying..."
		sleep 3
		rm -rf "$WORKDIR"
		continue
	fi

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
		if ! scp $SCP_OPTS "$REMOTE:$STAGING/db_current.tar.gz" "$WORKDIR/repo.db.tar.gz"; then
			echo "Failed to download repo DB, retrying..."
			sleep 3
			rm -rf "$WORKDIR"
			continue
		fi
		DB_MD5=$(md5sum "$WORKDIR/repo.db.tar.gz" | cut -d' ' -f1)
		cp "$PKGFILE" "$WORKDIR/"
		if ! (cd "$WORKDIR" && repo-add -R repo.db.tar.gz "$PKGNAME"); then
			echo "repo-add failed, retrying..."
			sleep 3
			rm -rf "$WORKDIR"
			continue
		fi
		if [ ! -f "$WORKDIR/repo.db.tar.gz" ]; then
			echo "repo-add did not produce repo.db.tar.gz, retrying..."
			rm -rf "$WORKDIR"
			sleep 3
			continue
		fi
	else
		cp "$PKGFILE" "$WORKDIR/"
		if ! (cd "$WORKDIR" && repo-add repo.db.tar.gz "$PKGNAME"); then
			echo "repo-add failed, retrying..."
			sleep 3
			rm -rf "$WORKDIR"
			continue
		fi
		if [ ! -f "$WORKDIR/repo.db.tar.gz" ]; then
			echo "repo-add did not produce repo.db.tar.gz, retrying..."
			rm -rf "$WORKDIR"
			sleep 3
			continue
		fi
		DB_MD5="__first_deploy__"
	fi

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

	if ! scp $SCP_OPTS "$WORKDIR/repo.db.tar.gz" "$REMOTE:$STAGING/db_new.tar.gz"; then
		echo "SCP db_new failed, retrying..."
		sleep 3
		rm -rf "$WORKDIR"
		continue
	fi
	scp $SCP_OPTS "$WORKDIR/repo.db.tar.gz.old" "$REMOTE:$STAGING/db_old.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/repo.files.tar.gz" "$REMOTE:$STAGING/db_files.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/repo.files.tar.gz.old" "$REMOTE:$STAGING/db_files_old.tar.gz" 2>/dev/null || true
	scp $SCP_OPTS "$WORKDIR/index.html" "$REMOTE:$STAGING/" 2>/dev/null || true

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

  if [ "$EXPECTED_MD5" != "__first_deploy__" ]; then
    CURRENT_MD5=$(md5sum "$REPO_PATH/repo.db.tar.gz" 2>/dev/null | cut -d' ' -f1 || echo "none")
    STAGED_MD5=$(md5sum "$STAGING/db_current.tar.gz" 2>/dev/null | cut -d' ' -f1 || echo "missing")
    if [ "$CURRENT_MD5" != "$STAGED_MD5" ]; then
      echo "CONFLICT"
      exit 0
    fi
  fi

  if [ ! -f "$STAGING/db_new.tar.gz" ]; then
    echo "MISSING_DB"
    exit 0
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
