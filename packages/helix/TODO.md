# TODO

- [ ] Вернуть сборку tree-sitter grammars в PKGBUILD

  Сейчас grammars исключены — пользователь должен запускать `hx --grammar fetch && hx --grammar build` вручную (см. `helix.install`). Нужно добавить шаги `hx --grammar fetch` и `hx --grammar build` в `build()` и устанавливать скомпилированные `.so` в `/usr/lib/helix/runtime/grammars`.

  Для этого потребуется:
  - Добавить `git` в `makedepends` (уже есть для cargo fetch, но пригодится и для grammar fetch)
  - Добавить `gcc` в `makedepends` (для компиляции grammar `.so`)
  - После `cargo build` запускать grammar fetch/build внутри контейнера
  - Копировать `runtime/grammars/` в `$pkgdir/usr/lib/helix/runtime/`
  - Убрать `optdepends` на `helix-grammars` и сообщение из `helix.install`
