<div align="tight" dir="rtl">

# ⚙️ پیکربندی و فایل‌ها

این سند دقیقاً توضیح می‌دهد اسکریپت چه فایل‌هایی می‌سازد، هر بخش چه کاری می‌کند و چطور شخصی‌سازی‌شان کنید.

---

## ۱. نقشهٔ فایل‌های تولیدشده

| فایل | سیستم | نقش |
|---|---|---|
| `~/.litellm/config.yaml` | لینوکس (WSL) | پیکربندی LiteLLM: لیست مدل‌ها و تنظیمات |
| `~/.litellm/master_key.txt` | لینوکس (WSL) | کلید احراز هویت پروکسی (دسترسی `600`) |
| `/etc/docker/daemon.json` | لینوکس (WSL) | میرورهای ایرانی داکرهاب |
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

## ۶. شخصی‌سازی‌های رایج

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

1. متغیر `LITELLM_PORT` در ابتدای اسکریپت `LiteLLM` را تغییر دهید (مثلاً `4010`).
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
