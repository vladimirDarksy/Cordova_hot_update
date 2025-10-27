# CONTEXT_{Module}_{OptionalFeature}

> Краткое описание модуля в одно предложение
> Обновлено: YYYY-MM-DD

---

## Назначение

Что делает модуль. Ключевые задачи. 2-3 предложения максимум.

---

## Ключевые файлы

| Файл | Строки | Назначение |
|------|--------|-----------|
| `path/to/File.js` | 1-200 | Краткое описание |
| `path/to/File.m` | 50-150 | Краткое описание |

---

## Архитектура

```
ComponentA
├── SubComponentB
│   ├── DetailC
│   └── DetailD
└── SubComponentE
    └── DetailF
```

**Описание компонентов:**
- ComponentA: назначение
- SubComponentB: назначение
- DetailC: назначение

---

## Data Models

### ModelName (Object/Structure)
```
property1: Type
property2: Type
computed: Type
```

**Важные поля:**
- `property1`: назначение
- `computed`: как вычисляется

---

## Data Flow

### Основной Flow

```
User Action → Component
  ↓
Method call
  ↓
Data operation
  ↓
Callback/Delegate
  ↓
UI update
```

**Files:** `File.js:X-Y`, `File.m:A-B`

### Операция: [Название]

```
Step 1
  ↓
Step 2
  ↓
Step 3
```

---

## Ключевые методы

### `methodName(param:)`
`File.js:X-Y` or `File.m:X-Y`
- Что делает (1 строка)
- Важные детали через bullet points
- Возвращает: Type

### `anotherMethod()`
`File.m:Z-W`
- Назначение
- Особенности

---

## Thread Safety / Concurrency

**Правила:**
- ВСЕГДА: ...
- НИКОГДА: ...

**Objective-C:**
```objc
[self.commandDelegate runInBackground:^{
    // Async operations
}];
```

---

## Known Issues

### Issue Name
- Причина: ...
- Решение: ...
- File: `File.m:X`

---

## История изменений

### YYYY-MM-DD
- Изменение 1
- Изменение 2
- Files: `File.m:X-Y`

### YYYY-MM-DD (Создание)
- Создан контекстный файл
- Задокументирована архитектура

---

*Версия X.Y | Обновлён: YYYY-MM-DD*
