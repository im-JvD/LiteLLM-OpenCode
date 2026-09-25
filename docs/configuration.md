<div align="tight" dir="rtl">

# ⚙️ پیکربندی و فایل‌ها

این سند دقیقاً توضیح می‌دهد اسکریپت چه فایل‌هایی می‌سازد، هر بخش چه کاری می‌کند و چطور شخصی‌سازی‌شان کنید.

---

## ۱. نقشهٔ فایل‌های تولیدشده

| فایل | سیستم | نقش |
|---|---|---|
| `~/.litellm/config.yaml` | لینوکس (WSL) | پیکربندی LiteLLM: لیست مدل‌ها و تنظیمات |
| `~/.litellm/master_key.txt` | لینوکس (WSL) | کلید احراز هویت پروکسی (دسترسی `600`) |
| `~/.litellm/dashboard_credentials.txt` | لینوکس (WSL) | اطلاعات ورود پنل مدیریت: URL + Username + Password |
| `~/.litellm/db_password.txt` | لینوکس (WSL) | رمز دیتابیس Postgres پنل مدیریت (دسترسی `600`) |
| `~/.litellm/pgdata/` | لینوکس (WSL) | داده‌های ماندگار دیتابیس Admin UI |
| `/etc/docker/daemon.json` | لینوکس (WSL) | میرورهای ایرانی داکرهاب |
| `/usr/local/bin/litellm` | لینوکس (WSL) | دستورات مدیریت سریع (up/down/restart/…) |
| `/usr/local/bin/litellm-boot.sh` | لینوکس (WSL) | اسکریپت استارت خودکار در بوت WSL |
| `/etc/systemd/system/litellm.service` یا `/etc/wsl.conf` | لینوکس (WSL) | مکانیزم اجرای خودکار (بسته به وجود systemd) |
| `%USERPROFILE%\.config\opencode\opencode.json` | ویندوز | اتصال OpenCode به پروکسی |

---

## ۲. ساختار `config.yaml`

نمونهٔ خروجی وقتی هر ۵ کلید داده شده باشد:

```yaml
model_list:
  # ---------------- Groq (fast inference) ----------------
  - model_name: qwen-2.5-coder-32b
    litellm_params:
      model: groq/qwen-2.5-coder-32b
      api_key: os.environ/GROQ_API_KEY
      api_base: https://api.groq.com/openai/v1
  - model_name: llama-3.3-70b-versatile
    litellm_params:
      model: groq/llama-3.3-70b-versatile
      api_key: os.environ/GROQ_API_KEY
      api_base: https://api.groq.com/openai/v1
  # ---------------- OpenRouter (free coding models) ----------------
  - model_name: deepseek/deepseek-chat-v3:free
    litellm_params:
      model: openrouter/deepseek/deepseek-chat-v3:free
      api_key: os.environ/OPENROUTER_API_KEY
      api_base: https://openrouter.ai/api/v1
  - model_name: deepseek/deepseek-r1:free
    litellm_params:
      model: openrouter/deepseek/deepseek-r1:free
      api_key: os.environ/OPENROUTER_API_KEY
      api_base: https://openrouter.ai/api/v1
  # ---------------- Google AI Studio (Gemini) ----------------
  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: os.environ/GEMINI_API_KEY
  # ---------------- Cerebras ----------------
  - model_name: llama3.1-70b
    litellm_params:
      model: cerebras/llama3.1-70b
      api_key: os.environ/CEREBRAS_API_KEY
      api_base: https://api.cerebras.ai/v1
  # ---------------- Mistral ----------------
  - model_name: codestral-latest
    litellm_params:
      model: mistral/codestral-latest
      api_key: os.environ/MISTRAL_API_KEY
      api_base: https://api.mistral.ai/v1

litellm_settings:
  drop_params: true        # پارامترهای پشتیبانی‌نشده بی‌صدا حذف می‌شوند

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

### نکات کلیدی

- **`model_name`** همان نامی است که OpenCode می‌بیند.
- **`model`** با پیشوند ارائه‌دهنده (`groq/`، `openrouter/` و…) به LiteLLM می‌گوید درخواست را کجا بفرستد.
- **`api_key: os.environ/...`** یعنی کلید از متغیر محیطی کانتینر خوانده می‌شود — کلید واقعی **هرگز داخل فایل نوشته نمی‌شود**.
- **`api_base`** صریح نوشته شده تا هیچ‌وقت به آدرس پیش‌فرض اشتباه نرود (مدل Gemini نیازی به آن ندارد).
- **`drop_params: true`** جلوی خطاهایی را می‌گیرد که از فرستادن پارامترهای اختصاصی یک ارائه‌دهنده به ارائه‌دهندهٔ دیگر پیش می‌آید.

---

## ۳. Master Key

- هنگام نصب یک کلید تصادفی ۶۴ کاراکتری ساخته می‌شود: `sk-` + خروجی `openssl rand -hex 32`.
- در `~/.litellm/master_key.txt` ذخیره (دسترسی `600`) و به‌عنوان `LITELLM_MASTER_KEY` به کانتینر تزریق می‌شود.
- هر درخواست به پروکسی (از جمله از سمت OpenCode) باید این کلید را در هدر `Authorization: Bearer ...` بفرستد.
- اگر master key را گم کردید: `cat ~/.litellm/master_key.txt`

---

## ۴. اجرای کانتینر

معادل دستوری که اسکریپت اجرا می‌کند:

```bash
sudo docker run -d \
  --name litellm \
  --restart unless-stopped \
  -p 4000:4000 \
  -v ~/.litellm/config.yaml:/app/config.yaml:ro \
  -e LITELLM_MASTER_KEY="sk-..." \
  -e GROQ_API_KEY="..." \
  ghcr.io/berriai/litellm:main-latest \
  --config /app/config.yaml \
  --port 4000
```

- `--restart unless-stopped`: با ری‌استارت WSL/ویندوز خودکار بالا می‌آید (مگر اینکه خودتان stop کرده باشید).
- `-v ...:ro`: کانفیگ فقط-خواندنی mount می‌شود.
- پارامترهای پایانی، آرگومان‌های CLI باینری `litellm` داخل ایمیج هستند.

---

## ۵. ساختار `opencode.json` (سمت ویندوز)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "litellm/qwen-2.5-coder-32b",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Proxy (Local)",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "sk-..."
      },
      "models": {
        "qwen-2.5-coder-32b": { "name": "Qwen 2.5 Coder 32B (Groq, free)" },
        "llama-3.3-70b-versatile": { "name": "Llama 3.3 70B Versatile (Groq, free)" }
      }
    }
  }
}
```

| فیلد | توضیح |
|---|---|
| `model` | مدل پیش‌فرض — اولین مدلِ کدنویسیِ موجود بر اساس کلیدهای شما (اولویت: Groq → OpenRouter → Gemini → Cerebras → Mistral) |
| `provider.litellm.npm` | درایور استاندارد OpenAI-Compatible از SDK لازم برای OpenCode |
| `baseURL` | آدرس پروکسی؛ چون WSL2 پورت‌ها را با ویندوز به اشتراک می‌گذارد، `127.0.0.1` از ویندوز هم کار می‌کند |
| `apiKey` | همان Master Key |
| `models` | فقط مدل‌های ارائه‌دهنده‌هایی که کلیدشان را داده‌اید |

---

## ۶. پنل مدیریت (UI)

LiteLLM یک رابط وب مدیریت دارد که با نصب، روی این آدرس فعال می‌شود:

```
http://127.0.0.1:4000/ui
```

- در مرورگر **ویندوز** باز کنید (WSL2 پورت را به ویندوز منتقل می‌کند).
- نام کاربری: `admin` — رمز عبور: همان **Master Key** (پسورد جداگانه وجود ندارد).
- ⚠️ ورود به UI به دیتابیس نیاز دارد؛ نصاب به‌طور خودکار کانتینر `litellm-db` (Postgres) را می‌سازد و `DATABASE_URL` را به پروکسی می‌دهد. داده‌های DB در `~/.litellm/pgdata` ماندگارند و رمز DB در `~/.litellm/db_password.txt` (دسترسی 600) ذخیره می‌شود.
- این اطلاعات با متغیرهای `UI_USERNAME` و `UI_PASSWORD` روی کانتینر تنظیم شده‌اند.
- دیدن سریع اطلاعات ورود: `litellm credentials`
- یک کپی هم در `~/.litellm/dashboard_credentials.txt` ذخیره می‌شود (دسترسی 600).
- از این پنل می‌توانید مدل‌ها را تست کنید، لاگ ببینید و مصرف را ببینید.

---

## ۷. اجرای خودکار در بوت WSL (Persistence)

خاموش/روشن شدن ویندوز باعث می‌شود WSL هم ری‌استارت شود. اسکریپت برای «همیشه روشن ماندن» دو لایه می‌سازد:

1. سیاست `--restart unless-stopped` روی خود کانتینر (داخل داکر).
2. استارت خودکار دیمن داکر + کانتینر در بوت WSL، با یکی از این دو مکانیزم:
   - **systemd** (اگر فعال باشد): سرویس `litellm.service` — مدیریت با `systemctl status litellm`
   - **boot command**: خط `command = /usr/local/bin/litellm-boot.sh` در `/etc/wsl.conf` (بدون systemd)

> 💡 برای فعال‌سازی systemd (پیشنهادی) در `/etc/wsl.conf` این را بگذارید و بعد `wsl --shutdown` کنید:
> ```ini
> [boot]
> systemd=true
> ```

می‌توانید حالت را هم اجبار کنید — قبل از اجرای نصاب:

```bash
LITELLM_BOOT_MODE=systemd bash LiteLLM.sh   # فقط سرویس systemd
LITELLM_BOOT_MODE=wslconf bash LiteLLM.sh   # فقط boot command در /etc/wsl.conf
# پیش‌فرض: تشخیص خودکار (auto)
```

---

## ۸. دستورات مدیریت سریع (`litellm` CLI)

نصب، یک CLI به نام `litellm` در `/usr/local/bin` می‌سازد:

| دستور | کار |
|---|---|
| `litellm up` | استارت دیمن داکر (اگر خاموش باشد) + کانتینر + انتظار برای سلامت |
| `litellm down` | توقف کانتینر |
| `litellm restart` | ری‌استارت + انتظار برای سلامت |
| `litellm status` | وضعیت کانتینر، policy، سلامت، آدرس پنل و مسیر فایل‌ها |
| `litellm credentials` | نمایش URL/نام‌کاربری/پسورد پنل مدیریت (پسورد = Master Key) |
| `litellm doctor` | تشخیص عمیق: اتصال هر ارائه‌دهنده + تست چت واقعی برای تک‌تک مدل‌ها |
| `litellm logs` | دنبال‌کردن زندهٔ لاگ‌ها |
| `litellm uninstall` | حذف کامل همه‌چیز (با تأیید) — معادل گزینهٔ ۲ نصاب |

> ⚠️ اگر روزی LiteLLM را با `pip install litellm` در خود WSL نصب کنید، باینری pip جای این CLI را در PATH می‌گیرد. برای پروکسی داکری نیازی به pip نیست.

---

## ۹. متغیرهای محیطی نصاب

قبل از اجرای نصاب می‌توانید رفتار آن را با متغیرهای محیطی تنظیم کنید:

| متغیر | پیش‌فرض | کاربرد |
|---|---|---|
| `LITELLM_BOOT_MODE` | `auto` | حالت استارت خودکار: `auto` / `systemd` / `wslconf` |
| `LITELLM_IMAGE` | `ghcr.io/berriai/litellm:main-latest` | ایمیج سفارشی (رجیستری دلخواه) |
| `LITELLM_GHCR_MIRROR` | خالی | میرور جایگزین ghcr (مثلاً `ghcr.nju.edu.cn`) — فقط وقتی pull مستقیم شکست خورد استفاده می‌شود |
| `LITELLM_PULL_RETRIES` | `3` | تعداد تلاش مجدد pull قبل از fallback |
| `LITELLM_KEY_CHECK` | `1` | تست زندهٔ هر کلید API به سرویس‌دهنده‌اش قبل از ساخت کانتینر (`0` = غیرفعال) |
| `LITELLM_KEY_CHECK_TIMEOUT` | `10` | مهلت ثانیه‌ای هر تست کلید |
| `LITELLM_DOCTOR_TIMEOUT` | `45` | مهلت ثانیه‌ای تست زندهٔ هر مدل در `litellm doctor` |
| `LITELLM_UI_DB` | `1` | `1` = کانتینر Postgres برای ورود به Admin UI ساخته می‌شود؛ `0` = بدون DB (UI لاگین ندارد، چت سالم است) |
| `LITELLM_DB_IMAGE` | `postgres:16-alpine` | ایمیج دیتابیس Admin UI (از داکرهاب و از مسیر میرورها) |

نمونه:

```bash
LITELLM_GHCR_MIRROR=ghcr.nju.edu.cn LITELLM_PULL_RETRIES=5 bash LiteLLM.sh
```

---

## ۱۰. شخصی‌سازی‌های رایج

### آیا باید برای OpenCode جداگانه «کلید مجازی» بسازیم؟

نه. کلیدی که OpenCode به آن وصل می‌شود همان **Master Key** است و نصاب از قبل آن را داخل `opencode.json` (فیلد `apiKey`) نوشته است. برای اطمینان:

```bash
litellm credentials     # پسورد داشبورد (همان Master Key)
grep apiKey "$(wslpath "$([ -x /usr/bin/powershell.exe ] && powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('UserProfile')" | tr -d '\r')")/.config/opencode/opencode.json" 2>/dev/null || grep apiKey /mnt/c/Users/*/".config/opencode/opencode.json"
```

هر دو مقدار یکی هستند. دکمهٔ «Create Key» داخل داشبورد (Virtual Keys) فقط برای حالت‌های پیشرفته است: کلید جدا برای هر کلاینت، سقف مصرف و گزارش‌گیری تفکیکی — برای استفادهٔ تک‌کاربره ضرورتی ندارد.

### افزودن مدل جدید

بخش زیر را به `model_list` در `config.yaml` اضافه کنید (نمونه برای یک مدل Groq دیگر):

```yaml
  - model_name: llama-3.1-8b-instant
    litellm_params:
      model: groq/llama-3.1-8b-instant
      api_key: os.environ/GROQ_API_KEY
      api_base: https://api.groq.com/openai/v1
```

و معادلش را در `models` فایل `opencode.json` ویندوز:

```json
"llama-3.1-8b-instant": { "name": "Llama 3.1 8B Instant (Groq, free)" }
```

سپس کانتینر را ری‌استارت کنید:

```bash
sudo docker restart litellm
```

### تغییر پورت

1. متغیر `LITELLM_PORT` در ابتدای اسکریپت `LiteLLM.sh` را تغییر دهید (مثلاً `4010`).
2. دوباره گزینهٔ `1` (نصب) را اجرا کنید — کانتینر قبلی حذف و با پورت جدید ساخته می‌شود و `opencode.json` هم به‌روز می‌شود.

### تغییر نام کانتینر یا مسیر کانفیگ

هر دو در ابتدای اسکریپت به‌صورت متغیر تعریف شده‌اند: `CONTAINER_NAME` و `LITELLM_DIR`.

### به‌روزرسانی ایمیج LiteLLM

```bash
sudo docker pull ghcr.io/berriai/litellm:main-latest
sudo docker rm -f litellm
# سپس دوباره گزینهٔ 1 اسکریپت را اجرا کنید
```

</div>
