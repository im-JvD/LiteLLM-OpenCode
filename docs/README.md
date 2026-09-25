<div align="tight" dir="rtl">

# 📚 مستندات LiteLLM ↔ OpenCode Bridge

این پوشه مرجع کامل مستندات فارسی پروژه است.

---

## 📑 فهرست مستندات

| سند | محتوا |
|---|---|
| [installation.md](installation.md) | پیش‌نیازها، روش‌های اجرا (یک‌خطی از گیت‌هاب یا دستی)، مراحل تعاملی نصب، دریافت کلیدهای API و راه‌اندازی نهایی OpenCode |
| [configuration.md](configuration.md) | شرح کامل `config.yaml` و `opencode.json`، سازوکار Master Key و متغیرهای محیطی، افزودن مدل جدید و تغییر پورت |
| [uninstall.md](uninstall.md) | حذف کامل: چه چیزی پاک می‌شود، چه چیزی عمداً حفظ می‌شود و روش‌های حذف دستی |
| [troubleshooting.md](troubleshooting.md) | جدول عیب‌یابی خطاهای رایج: 403 تحریم، دیمن داکر، PowerShell، تداخل پورت و… |

---

## 🔗 لینک‌های مرتبط

- [README اصلی پروژه](../README.md)
- [مستندات تست‌ها](../tests/README.md)

---

## 🗺️ نقشهٔ کلی معماری

```
┌─────────────────────────── Windows ───────────────────────────┐
│                                                               │
│   OpenCode  ──خواندن──>  %USERPROFILE%\.config\opencode\      │
│     │                      opencode.json                      │
│     │                      (provider: litellm)                │
└─────┼─────────────────────────────────────────────────────────┘
      │  http://127.0.0.1:4000/v1   (Bearer: Master Key)
┌─────▼────────────────────── WSL2 Ubuntu ──────────────────────┐
│                                                               │
│   Docker container: litellm  (--restart unless-stopped)       │
│     ├── image: ghcr.io/berriai/litellm:main-latest            │
│     ├── config: ~/.litellm/config.yaml  (فقط-خواندنی)         │
│     └── keys: متغیرهای محیطی (GROQ_API_KEY و…)                │
│                                                               │
│   /etc/docker/daemon.json  ← میرورهای ایرانی (رفع 403)        │
└───────────────────────────────────────────────────────────────┘
      │
      ▼  درخواست‌های مدل
   Groq │ OpenRouter │ Google AI │ Cerebras │ Mistral
```

</div>
