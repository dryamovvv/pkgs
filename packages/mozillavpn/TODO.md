# TODO: mozillavpn

## Headless build

- [ ] Создать патч для headless-сборки без Qt GUI
  - Убрать `find_package(Qt6 ... Gui Qml Quick QuickControls2 QuickTest Widgets Svg)` из корневого CMakeLists.txt
  - Убрать `add_subdirectory(lottie)`, `add_subdirectory(tools/qml_hot_reload)`
  - В `src/CMakeLists.txt`: убрать `find_package(Qt6 REQUIRED COMPONENTS Svg GuiPrivate QmlPrivate)`
  - Убрать `target_link_libraries(... Qt6::Quick Qt6::QuickControls2 Qt6::Widgets Qt6::Svg)`
  - Убрать `add_subdirectory(ui)` и `target_link_libraries(... mozillavpn-uiplugin)`
  - Убрать GUI-специфичные исходники из `cmake/sources.cmake`: `commandui.cpp`, `ui/resources.qrc`, etc.
  - Убрать GUI-специфичные исходники из `cmake/shared-sources.cmake`: `qmlengineholder`, `fontloader`, `theme`, `frontend/*`, etc.
- [ ] Убрать runtime-зависимости: `qt6-declarative`, `qt6-svg`, `qt6-5compat`
- [ ] Протестировать сборку в CI
- [ ] Проверить команды: `mozillavpn linuxdaemon`, `activate`, `deactivate`, `status`, `wgconf`
