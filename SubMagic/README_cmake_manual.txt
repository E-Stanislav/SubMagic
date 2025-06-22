# Инструкция: ручное копирование cmake для sandbox-приложения

1. Найдите бинарь cmake, установленный Homebrew:
   ```zsh
   which cmake
   # Например: /opt/homebrew/bin/cmake
   ls -l /opt/homebrew/bin/cmake
   # Это симлинк, смотрим на что указывает:
   readlink /opt/homebrew/bin/cmake
   # Например: ../Cellar/cmake/4.0.3/bin/cmake
   # Полный путь: /opt/homebrew/Cellar/cmake/4.0.3/bin/cmake
   ```

2. Скопируйте бинарь cmake в папку проекта (например, SubMagic/bin):
   ```zsh
   mkdir -p /Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin
   cp /opt/homebrew/Cellar/cmake/4.0.3/bin/cmake /Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/cmake
   chmod +x /Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/cmake
   ```

3. В настройках приложения укажите путь:
   ```
   /Users/stanislave/Documents/Projects/SubMagic/SubMagic/bin/cmake
   ```

4. Теперь sandbox-приложение всегда сможет использовать этот бинарь, пока он лежит в проекте.

---

**Важно:**
- Если проект будет перемещён, путь нужно будет обновить.
- Для production лучше копировать бинарь внутрь Application Support, но для разработки этот способ надёжен.
