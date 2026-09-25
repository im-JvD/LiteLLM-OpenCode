<div align="tight" dir="rtl">

# 🚀 LiteLLM ↔ OpenCode Bridge

نصب‌کننده و پیکربندی‌کنندهٔ یک‌مرحله‌ای **پروکسی LiteLLM** داخل **WSL2 Ubuntu** و اتصال آن به ابزار برنامه‌نویسی هوش مصنوعی **OpenCode** در ویندوز — بدون نیاز به build، با ایمیج آماده و میرورهای ایرانی برای دور زدن تحریم‌ها.

---

## ⚡ اجرای سریع (یک دستور)

داخل ترمینال **WSL2 Ubuntu** کافی است اجرا کنید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)
```

یا با `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)
```

> ⚠️ **نکتهٔ مهم:** حتماً از حالت `bash <( curl ... )` استفاده کنید، نه `curl ... | bash`؛ چون اسکریپت تعاملی است و باید بتواند از شما سؤال بپرسد. اگر خواستید اول دانلود کنید:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh -o /tmp/LiteLLM.sh
> bash /tmp/LiteLLM.sh
> ```
>
> 📝 اگر فایل را **دستی در ویندوز ذخیره می‌کنید** و خطایی مثل `set: pipefail: invalid option name` دیدید، مشکل خط‌پایان ویندوزی (CRLF) است — راه‌حل در [عیب‌یابی](docs/troubleshooting.md). (اسکریپت در اجرای `bash LiteLLM.sh` خودش این حالت را ترمیم می‌کند.)

---

## ✨ ویژگی‌ها

| ویژگی | توضیح |
|---|---|
| 🖥️ منوی تعاملی | گزینهٔ `1` نصب کامل، گزینهٔ `2` حذف کامل |
| 🐳 نصب داکر بدون تحریم | از مخازن `apt` اوبونتو (`docker.io`) — بدون `get.docker.com` |
| 🇮🇷 میرورهای ایرانی | ArvanCloud، Liara و IranServer در `/etc/docker/daemon.json` برای رفع خطای 403 |
| 📦 بدون build | فقط ایمیج آمادهٔ `ghcr.io/berriai/litellm:main-latest` |
| 🔑 ۵ کلید API | Groq، OpenRouter، Google AI، Cerebras، Mistral (حداقل یک کلید اجباری) |
| 🧠 ۷ مدل کدنویسی | ساخت خودکار `config.yaml` فقط بر اساس کلیدهایی که داده‌اید |
| 🔁 اجرای پایدار | کانتینر با `--restart unless-stopped` روی پورت 4000 |
| 🖥️ پنل مدیریت | رابط وب LiteLLM روی `http://127.0.0.1:4000/ui` (admin / Master Key) |
| ⚙️ استارت خودکار در بوت WSL | سرویس systemd یا boot command در `/etc/wsl.conf` |
| ⌨️ CLI مدیریت | `litellm up / down / restart / status / logs / uninstall` |
| 🪟 تشخیص هوشمند ویندوز | پیدا کردن مسیر پروفایل با PowerShell (حتی با فاصله در نام کاربری) |
| 🔒 کلید امن | ساخت خودکار Master Key و ذخیرهٔ امن آن |
| 🧪 تست‌شده | ۲۱ سناریوی شبیه‌سازی‌شده + تست واقعی E2E با خودِ LiteLLM |

---

## 🧠 مدل‌های پشتیبانی‌شده

| مدل | ارائه‌دهنده | کاربرد |
|---|---|---|
| `qwen-2.5-coder-32b` | Groq | کدنویسی سریع (رایگان) |
| `llama-3.3-70b-versatile` | Groq | مدل عمومی قدرتمند (رایگان) |
| `deepseek/deepseek-chat-v3:free` | OpenRouter | چت و کدنویسی (رایگان) |
| `deepseek/deepseek-r1:free` | OpenRouter | استدلال عمیق (رایگان) |
| `gemini-2.0-flash` | Google AI | سرعت بالا + کانتکست بزرگ (رایگان) |
| `llama3.1-70b` | Cerebras | استنتاج فوق‌سریع (رایگان) |
| `codestral-latest` | Mistral | تخصصی کدنویسی |

---

## 📋 پیش‌نیازها

- ویندوز ۱۰/۱۱ با **WSL2** و توزیع **Ubuntu** (تست‌شده روی Ubuntu 22.04+)
- نصب‌شده بودن **OpenCode** در سمت ویندوز
- دسترسی `sudo` در اوبونتو
- اتصال اینترنت (برای `apt` و `ghcr.io` — داکرهاب تحریم است ولی ghcr معمولاً باز است)

---

## 📁 ساختار مخزن

```
LiteLLM-OpenCode/
├── LiteLLM.sh                  ← اسکریپت اصلی (قابل اجرای مستقیم از GitHub)
├── docs/                    ← مستندات کامل فارسی
│   ├── README.md            ← فهرست مستندات
│   ├── installation.md      ← راهنمای گام‌به‌گام نصب
│   ├── configuration.md     ← شرح کامل فایل‌های پیکربندی
│   ├── uninstall.md         ← راهنمای حذف کامل
│   └── troubleshooting.md   ← عیب‌یابی خطاهای رایج
└── tests/                   ← تست‌های خودکار + نتایج اجرا
    ├── README.md            ← مستندات تست‌ها
    ├── run_all_tests.sh     ← سوئیت ۱۷ سناریویی آفلاین
    ├── e2e_litellm_real.sh  ← تست واقعی E2E با LiteLLM
    ├── e2e_real_docker.sh   ← تست واقعی E2E با Docker (روی WSL2)
    ├── helpers/stubbin/     ← بدل‌های ایزوله برای تست
    └── results/             ← نتایج ثبت‌شدهٔ اجراها
```

---

## 📚 مستندات

- [راهنمای نصب گام‌به‌گام](docs/installation.md)
- [پیکربندی و فایل‌ها](docs/configuration.md)
- [حذف کامل (Uninstall)](docs/uninstall.md)
- [عیب‌یابی خطاهای رایج](docs/troubleshooting.md)
- [مستندات تست‌ها](tests/README.md)

---

## 🔒 نکتهٔ امنیتی

کلیدهای API شما فقط به‌صورت متغیر محیطی به کانتینر LiteLLM تزریق می‌شوند و داخل `config.yaml` نوشته **نمی‌شوند**. Master Key هم در `~/.litellm/master_key.txt` با دسترسی `600` ذخیره می‌شود. هرگز این فایل‌ها را در مخازن عمومی قرار ندهید.

</div>
