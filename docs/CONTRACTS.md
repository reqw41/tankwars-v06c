# Общие правила для исполнителей (tankwars-v06c)

1. Рабочая папка — только `~/projects/tankwars-v06c`. Ничего не хранить в /tmp: временное — в `work/<задача>/`.
2. Оригиналы в `orig/` и исходные `re/bomb25.exe`, `re/bomb25.ovr` не менять.
3. Никаких клавиш/кликов в GUI хоста (osascript, CGEvent, activate). Ghidra — только headless
   (`analyzeHeadless`), DOSBox — только без окна. Не убивать чужие процессы.
4. Числа в отчётах — только из файлов, извлечённых скриптом (скрипт кладётся в репо). Не вписывать руками.
5. В отчёте раздельно: «Доказано» (со ссылкой на адрес/байты/скрипт) и «Гипотезы».
6. Git: коммитить только свои файлы, не делать stash/checkout/reset чужого. Одна задача — один исполнитель.
7. Ghidra: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`,
   `G=$(brew --prefix ghidra)/libexec; $G/support/analyzeHeadless ...`. Пересборка проекта — команда из `re/NOTES.md`.
8. Перед работой прочитать `re/NOTES.md`; новые устойчивые факты дописывать туда (раздел своей задачи).
