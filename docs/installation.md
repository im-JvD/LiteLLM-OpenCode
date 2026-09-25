<div align="tight" dir="rtl">

# 📥 راهنمای نصب گام‌به‌گام

---

## ۱. پیش‌نیازها

| پیش‌نیاز | بررسی |
|---|---|
| ویندوز ۱۰/۱۱ | — |
| WSL2 با توزیع Ubuntu | `wsl -l -v` در PowerShell → ستون VERSION باید `2` باشد |
| OpenCode در ویندوز | نصب طبق [opencode.ai](https://opencode.ai) |
| دسترسی sudo در اوبونتو | اجرای `sudo -v` در ترمینال اوبونتو |
| اینترنت | برای `apt` (مخازن ایران آزاد است) و `ghcr.io` |

اگر WSL2 ندارید، اول در PowerShell (با دسترسی Administrator) اجرا کنید:

```powershell
wsl --install -d Ubuntu
```

---

## ۲. روش‌های اجرای اسکریپت

### روش ۱: اجرای مستقیم از گیت‌هاب (پیشنهادی) ⭐

داخل ترمینال **WSL Ubuntu**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)
```

یا:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)
```

> ⚠️ از الگوی `bash <( curl ... )` استفاده کنید نه `curl ... | bash`.
> در حالت دوم، ورودی استاندارد (stdin) که برای منو و دریافت کلیدها لازم است، توسط خودِ لوله (pipe) اشغال می‌شود و اسکریپت درست کار نمی‌کند.

### روش ۲: دانلود و سپس اجرا

```bash
curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh -o /tmp/LiteLLM.sh
bash /tmp/LiteLLM.sh
```

### روش ۳: کلون مخزن

```bash
git clone https://github.com/im-JvD/LiteLLM-OpenCode.git
cd LiteLLM-OpenCode
bash LiteLLM.sh
```

> 💡 اسکریپت را **بدون sudo** اجرا کنید؛ خودش در جای لازم ارتقای دسترسی می‌دهد. اگر با sudo اجرا کنید هم کار می‌کند ولی هشدار می‌دهد که کانفیگ‌ها زیر `/root` ساخته می‌شوند.

---

## ۳. منوی اصلی

بلافاصله این منو را می‌بینید:

```
=================================================================
     LiteLLM  <->  OpenCode  Bridge  |  WSL2 Ubuntu Setup
=================================================================

   Proxy target : ghcr.io/berriai/litellm:main-latest
   Proxy port   : 4000   (restart policy: unless-stopped)
   Linux config : /home/<user>/.litellm

   Please choose an option:

     1) Full Install    (Docker + LiteLLM proxy + OpenCode config)
     2) Full Uninstall  (remove container + all generated configs)
     q) Quit

   Enter your choice [1/2/q]:
```

برای نصب، عدد `1` را وارد کنید.

---

## ۴. مراحل نصب (گزینهٔ 1)

اسکریپت ۹ مرحله را به‌ترتیب انجام می‌دهد:

| مرحله | کار |
|---|---|
| 1/9 | بررسی محیط WSL2 و موجود بودن `powershell.exe` |
| 2/9 | نصب داکر از مخازن apt اوبونتو (`docker.io`) — اگر از قبل نباشد |
| 3/9 | نوشتن میرورهای ایرانی در `/etc/docker/daemon.json` (با بکاپ از فایل قبلی) |
| — | راه‌اندازی دیمن داکر + فعال‌سازی auto-start در صورت وجود systemd |
| 4/9 | دریافت ۵ کلید API (پایین‌تر را ببینید) |
| 5/9 | ساخت `~/.litellm/config.yaml` و Master Key |
| 6/9 | دانلود ایمیج آمادهٔ `ghcr.io/berriai/litellm:main-latest` |
| 7/9 | اجرای کانتینر روی پورت 4000 با `--restart unless-stopped` |
| 8/9 | پیکربندی اجرای خودکار در بوت WSL + نصب دستورات مدیریت `litellm` |
| 9/9 | ساخت `opencode.json` در پروفایل ویندوز |

---

## ۵. دریافت و وارد کردن کلیدهای API

اسکریپت ۵ کلید می‌پرسد. **کلیدی ندارید؟ فقط Enter بزنید** تا رد شود — اما **حداقل یک کلید الزامی است** (اگر هیچ کلیدی ندهید، دوباره سؤال می‌شود؛ حداکثر ۳ بار).

| ترتیب | سرویس | لینک دریافت کلید رایگان | پیشوند نمونه |
|---|---|---|---|
| 1 | Groq | [console.groq.com/keys](https://console.groq.com/keys) | `gsk_...` |
| 2 | OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) | `sk-or-...` |
| 3 | Google AI | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | `AIza...` |
| 4 | Cerebras | [cloud.cerebras.ai](https://cloud.cerebras.ai) | `csk-...` |
| 5 | Mistral | [console.mistral.ai/api-keys](https://console.mistral.ai/api-keys) | `...` |

نکته‌ها:

- کلیدها هنگام تأیید به‌صورت ماسک‌شده نمایش داده می‌شوند (مثلاً `gsk_****abcd`).
- فاصله‌های اضافی ابتدا و انتهای کلید به‌صورت خودکار حذف می‌شوند.
- فقط مدل‌های ارائه‌دهنده‌هایی که کلید داده‌اید ساخته می‌شوند.

---

## ۶. خروجی موفق نصب

در پایان باید این پیام را ببینید:

```
=================================================================
  INSTALLATION COMPLETED SUCCESSFULLY!
=================================================================

  LiteLLM endpoint (from Windows) : http://127.0.0.1:4000/v1

  ADMIN PANEL (UI) - open in the WINDOWS browser:
    URL       : http://127.0.0.1:4000/ui
    Username  : admin
    Password  : (the Master key below)

  Master key (also saved to)      : /home/<user>/.litellm/master_key.txt
  Master key                      : sk-...
  LiteLLM config file             : /home/<user>/.litellm/config.yaml
  OpenCode config file (Windows)  : /mnt/c/Users/<Name>/.config/opencode/opencode.json
  Container name                  : litellm
  Auto-start on WSL boot          : systemd service / wsl.conf boot command
  ...
```

---

## ۷. پنل مدیریت (UI)، اجرای خودکار و دستورات مدیریت

### پنل مدیریت LiteLLM

در مرورگر **ویندوز** باز کنید: `http://127.0.0.1:4000/ui`

| فیلد | مقدار |
|---|---|
| Username | `admin` |
| Password | همان **Master Key** — پسورد جداگانه‌ای وجود ندارد! |

🔑 **پسورد پنل دقیقاً همان Master Key است.** برای دیدن آن یکی از این راه‌ها:

```bash
litellm credentials                          # URL + username + password همه با هم
cat ~/.litellm/master_key.txt                # فقط کلید
cat ~/.litellm/dashboard_credentials.txt     # فایل مخصوص اطلاعات ورود داشبورد
```

رشته‌ای که با `sk-` شروع می‌شود را کپی کنید و در فرم لاگین پنل بچسبانید.

### اجرای خودکار در بوت WSL

اسکریپت بسته به وضعیت سیستم شما یکی از دو مکانیزم را نصب می‌کند:

- اگر **systemd** فعال باشد (`[boot] systemd=true` در `/etc/wsl.conf`): سرویس `litellm.service` ساخته و enable می‌شود که در بوت، داکر و سپس کانتینر را بالا می‌آورد.
- در غیر این صورت: یک **boot command** در `/etc/wsl.conf` اضافه می‌شود (`command = /usr/local/bin/litellm-boot.sh`) که موقع باز شدن WSL اجرا شده و داکر + کانتینر را start می‌کند.

در هر دو حالت، خود کانتینر هم `--restart unless-stopped` است؛ یعنی تا وقتی خودتان `litellm down` نزده باشید، همیشه بالا می‌ماند.

### دستورات مدیریت سریع

بعد از نصب، این دستورات در ترمینال WSL در دسترس‌اند:

```bash
litellm status     # وضعیت کانتینر، سلامت و مسیر فایل‌ها
litellm credentials # نمایش URL، نام کاربری و پسورد پنل مدیریت
litellm up         # روشن کردن (داکر و کانتینر)
litellm down       # خاموش کردن
litellm restart    # ری‌استارت + انتظار برای سلامت
litellm logs       # مشاهدهٔ زندهٔ لاگ‌ها (Ctrl+C برای خروج)
litellm uninstall  # حذف کامل (کانتینر، کانفیگ‌ها و خود CLI)
```

---

## ۸. راه‌اندازی OpenCode در ویندوز

1. یک **ترمینال جدید** ویندوز (PowerShell یا CMD) باز کنید.
2. وارد پوشهٔ پروژهٔ خود شوید: `cd C:\projects\my-app`
3. اجرا کنید: `opencode`
4. در لیست Provider ها گزینهٔ **«LiteLLM Proxy (Local)»** را انتخاب کنید و یکی از مدل‌ها را بچینید (مدل پیش‌فرض از قبل تنظیم شده است).

---

## ۹. بررسی سلامت نصب

داخل WSL:

```bash
sudo docker ps                       # کانتینر litellm باید Up باشد
curl -s http://127.0.0.1:4000/health/liveliness   # خروجی: I'm alive!
```

با احراز هویت و دیدن لیست مدل‌ها:

```bash
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $(cat ~/.litellm/master_key.txt)"
```

با مشکل مواجه شدید؟ → [troubleshooting.md](troubleshooting.md)

</div>
