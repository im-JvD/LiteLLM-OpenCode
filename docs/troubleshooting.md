<div align="tight" dir="rtl">

# 🛠️ عیب‌یابی خطاهای رایج

جدول زیر رایج‌ترین خطاها و راه‌حل‌های آن‌هاست. اگر مشکل شما اینجا نبود، در گیت‌هاب Issue باز کنید.

---

## 🔴 خطای `set: pipefail: invalid option name` (رایج‌ترین!)

**نشانه‌ها:** بلافاصله بعد از اجرا چنین پیام‌هایی می‌بینید (متن به‌هم‌ریخته، گاهی `: invalid option nameset: pipefail`):

```
: invalid option nameset: pipefail
```

**علت:** فایل با **خط‌پایان ویندوزی (CRLF)** ذخیره شده است. اگر فایل را در ویندوز با Notepad یا ادیتورهای مشابه ذخیره کنید، یا آن را از حالت‌های غیر raw کپی کنید، هر انتهای خط یک کاراکتر نامرئی `\r` اضافه می‌شود و bash آن را جزء دستورات می‌خواند.

**راه‌حل فوری** (روی همان فایل، داخل WSL):

```bash
sed -i 's/\r$//' LiteLLM.sh
bash LiteLLM.sh
```

یا:

```bash
dos2unix LiteLLM.sh 2>/dev/null || sed -i 's/\r$//' LiteLLM.sh
bash LiteLLM.sh
```

**پیشگیری:**

- بهترین راه، همان اجرای یک‌خطی با `curl` است — فایل مستقیم و با خط‌پایان درست (LF) به WSL می‌رسد و اصلاً از ویندوز رد نمی‌شود:

  ```bash
  bash <(curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)
  ```

- این اسکریپت از نسخهٔ فعلی مخزن، **محافظ self-heal** دارد: اگر نسخهٔ CRLF را با `bash LiteLLM.sh` اجرا کنید، خودش یک نسخهٔ تمیز می‌سازد و ادامهٔ نصب را با آن انجام می‌دهد (مگر در اجرای مستقیم `./LiteLLM.sh` که خطای shebang را همان اول می‌گیرید — در آن حالت از `bash LiteLLM.sh` استفاده کنید).

- اگر خودتان مخزن را در ویندوز clone می‌کنید، فایل `.gitattributes` موجود در مخزن جلوی تبدیل خط‌پایان را می‌گیرد.

---

## 🔴 خطاهای مرحلهٔ دانلود/داکر

### `docker pull` خطای 403، `toomanyrequests` یا `TLS handshake timeout` می‌دهد

اسکریپت ایمیج را از `ghcr.io` می‌گیرد (میرورهای `daemon.json` فقط برای داکرهاب هستند، نه ghcr). خطای `TLS handshake timeout` معمولاً **موقتی** است؛ اسکریپت خودش ۳ بار تلاش می‌کند و اگر ایمیج از نصب قبلی روی سیستم باشد، با آن ادامه می‌دهد.

راه‌های حل به ترتیب:

```bash
# ۱) اتصال به ghcr را بسنجید و دوباره نصاب را اجرا کنید (اغلب همان بار اول حل می‌شود)
curl -I https://ghcr.io/v2/
bash LiteLLM.sh

# ۲) VPN سمت ویندوز بزنید و دوباره اجرا کنید

# ۳) از یک میرور ghcr استفاده کنید (مثلاً میرور دانشگاه نانجینگ چین):
LITELLM_GHCR_MIRROR=ghcr.nju.edu.cn bash LiteLLM.sh

# ۴) یا ایمیج را کامل خودتان انتخاب کنید:
LITELLM_IMAGE=<registry>/berriai/litellm:main-latest bash LiteLLM.sh

# ۵) تعداد تلاش‌های مجدد هم قابل تغییر است:
LITELLM_PULL_RETRIES=5 bash LiteLLM.sh
```

نکته: اگر قبلاً pull موفق داشته‌اید، ایمیج هنوز لوکال است (`sudo docker images`) و نصاب با همان ادامه می‌دهد.

### `Cannot connect to the Docker daemon`

دیمن داکر بالا نیامده (معمولاً بعد از `wsl --shutdown`):

```bash
sudo service docker start
sudo docker ps
```

### `docker: command not found`

نصب داکر ناقص بوده:

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo service docker start
```

### `address already in use` روی پورت 4000

پورت اشغال است:

```bash
sudo ss -ltnp | grep 4000        # چه چیزی گرفته؟
sudo docker rm -f litellm        # اگر کانتینر قبلی است، حذف و نصب مجدد با پورت جدید
```

یا متغیر `LITELLM_PORT` در ابتدای اسکریپت را به مثلاً `4010` تغییر دهید و دوباره نصب کنید.

---

## 🟡 خطاهای مرتبط با ویندوز/PowerShell

### `powershell.exe was not found`

Interop ویندوز در WSL غیرفعال است. در ویندوز فایل `%USERPROFILE%\.wslconfig` را بسازید و مطمئن شوید این خط را ندارد یا `false` نیست:

```ini
[wsl2]
# بدون خط appendWindowsPath=false
```

سپس در PowerShell: `wsl --shutdown` و باز کردن مجدد ترمینال.

### مسیر پروفایل ویندوز اشتباه تشخیص داده می‌شود

اسکریپت فقط از PowerShell استفاده می‌کند (`[Environment]::GetFolderPath('UserProfile')`)؛ این متد حتی با OneDrive-redirect و فاصله در نام کاربری درست کار می‌کند. تست دستی:

```bash
powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('UserProfile')"
```

خروجی باید چیزی شبیه `C:\Users\Your Name` باشد.

### OpenCode پروایدر «LiteLLM Proxy (Local)» را نمی‌بیند

1. مسیر فایل را چک کنید: `%USERPROFILE%\.config\opencode\opencode.json`
2. JSON معتبر است؟ `python -m json.tool opencode.json` (در ویندوز) یا باز کردن در VSCode.
3. OpenCode را **کاملاً** ببندید و دوباره باز کنید.
4. نسخهٔ OpenCode به‌روز باشد.

---

## 🟠 خطاهای احراز هویت و درخواست‌ها

### OpenCode خطای `401` / `Unauthorized` می‌دهد

کلید OpenCode با Master Key پروکسی نمی‌خواند. بررسی:

```bash
cat ~/.litellm/master_key.txt
```

سپس فایل `%USERPROFILE%\.config\opencode\opencode.json` را در ویندوز باز کنید و مقدار `apiKey` را با خروجی بالا مقایسه کنید. هر دو باید یکسان باشند. ساده‌ترین راه هماهنگ‌سازی: دوباره گزینهٔ `1` را اجرا کنید تا هر دو فایل از نو و هماهنگ ساخته شوند.

### `429` یا `quota exceeded` از سمت ارائه‌دهنده

سهمیهٔ رایگان مدل تمام شده. مدل دیگری انتخاب کنید یا کلید همان سرویس را شارژ/تعویض کنید.

### کانتینر Up است ولی مدل جواب نمی‌دهد

لاگ‌ها را ببینید:

```bash
sudo docker logs -f litellm
```

اگر `401` از سمت Groq/Gemini و… می‌بینید، کلید همان ارائه‌دهنده اشتباه یا منقضی است — کلید درست را بگیرید و دوباره گزینهٔ `1` را اجرا کنید.

---

### خطای `403 Forbidden` از Groq (یا 401 از سایر ارائه‌دهنده‌ها) هنگام چت

پیام در داشبورد/لاگ:

```
GroqException - {"error":{"message":"Forbidden"}}
```

یعنی کلیدی که در خانهٔ Groq وارد شده، از نظر Groq نامعتبر است. رایج‌ترین علت: **کلیدها جابجا وارد شده‌اند** (مثلاً کلید OpenRouter در خانهٔ Groq). راه تشخیص سریع:

```bash
sudo docker inspect litellm | grep GROQ_API_KEY
```

- اگر با `gsk_` شروع نمی‌شود، همان جابجایی است.
- راه‌حل: نصاب را دوباره اجرا کنید، در سؤال «Keep these keys?» بزنید **`n`** و کلیدها را درست وارد کنید:
  - Groq → کلیدی که با `gsk_` شروع می‌شود
  - OpenRouter → کلیدی که با `sk-or-` شروع می‌شود

نصاب از این نسخه **هر کلید را قبل از ساخت کانتینر به‌صورت زنده تست می‌کند** و اگر کلیدی رد شود (401/403) همان لحظه اعلام و پیشنهاد اصلاح می‌دهد. نکته: «could not verify» یعنی شبکه به آن سرویس نمی‌رسد (مثلاً Google بدون VPN) — این شکست نیست؛ کلید ممکن است سالم باشد.

---

## 🟣 هشدار «does not look like a X key»

این هشدار یعنی کلیدی که در آن خانه وارد کرده‌اید با پیشوند شناخته‌شدهٔ آن سرویس نمی‌خواند — معمولاً یعنی کلیدها جابجا وارد شده‌اند (مثلاً کلید OpenRouter در خانهٔ Groq). پیشوندهای درست:

| سرویس | پیشوند |
|---|---|
| Groq | `gsk_` |
| OpenRouter | `sk-or-` |
| Google AI | `AIza` |
| Cerebras | `csk-` |
| Mistral | (پیشوند ثابتی ندارد، بررسی نمی‌شود) |

با کلید جابجا، نصب کامل می‌شود ولی موقع چت خطای 401 می‌گیرید. کافی است نصاب را دوباره اجرا کنید و کلیدها را درست وارد کنید.

---

## 🟢 خطاهای مدیریت و پنل

### `litellm: command not found`

CLI مدیریت نصب نشده یا حذف شده — دوباره گزینهٔ `1` نصاب را اجرا کنید. مسیر: `/usr/local/bin/litellm`.

### خطای «Authentication Error, Not connected to DB!» هنگام Login به پنل

این شناخته‌شده‌ترین محدودیت نسخه‌های جدید LiteLLM است: **ورود به Admin UI بدون یک دیتابیس Postgres اصلاً ممکن نیست** — حتی اگر نام کاربری و رمز را درست بزنید. پیام پشت صحنه:

```json
{"error":{"message":"Authentication Error, Not connected to DB!","type":"auth_error","code":"400"}}
```

نصاب این مشکل را کامل حل کرده: یک کانتینر Postgres به نام `litellm-db` کنار پروکسی بالا می‌آورد (از داکرهاب و از طریق میرورهای ایرانی) و `DATABASE_URL` را به کانتینر `litellm` می‌دهد. پس در نصب‌های جدید این خطا نباید ظاهر شود. اگر دیدید:

```bash
sudo docker ps                     # هر دو کانتینر litellm و litellm-db باید Up باشند
litellm restart                    # اولین بوت بعد از ساخت DB، مایگریشن انجام می‌دهد (کمی صبر)
sudo docker logs litellm 2>&1 | grep -i "database\|prisma" | tail -20
```

اگر قبل از این نسخه نصب کرده‌اید (بدون دیتابیس)، یک بار نصاب را دوباره اجرا کنید تا کانتینر DB هم ساخته شود.

- می‌خواهید بدون DB اجرا کنید؟ `LITELLM_UI_DB=0 bash LiteLLM.sh` — در این حالت UI لاگین ندارد ولی **چت از طریق OpenCode کاملاً کار می‌کند** (پروکسی به DB نیازی ندارد).

---

### پنل `http://127.0.0.1:4000/ui` باز نمی‌شود یا Login نمی‌شود

- پروکسی روشن است؟ `litellm status`
- نام کاربری دقیقاً `admin` و رمز همان Master Key است.
- ⚠️ **پسورد جداگانه وجود ندارد** — رشتهٔ `sk-...` همان پسورد است. همه را یکجا ببینید:

  ```bash
  litellm credentials
  # یا
  cat ~/.litellm/dashboard_credentials.txt
  ```

- پسورد را کپی کنید (بدون فاصلهٔ ابتدا/انتها) و در فرم بچسبانید.
- از مرورگر **ویندوز** باز کنید نه داخل WSL (هرچند هر دو کار می‌کند).

### بعد از ری‌استارت ویندوز/WSL کانتینر بالا نیامد

```bash
litellm up        # همین کافی است
```

بررسی مکانیزم استارت خودکار:

```bash
systemctl status litellm 2>/dev/null || grep -A1 '\[boot\]' /etc/wsl.conf
cat /tmp/litellm-boot.log
```

اگر systemd ندارید و می‌خواهید کانفیگ درست شود، دوباره گزینهٔ `1` را اجرا کنید.

---

## 🔵 موارد عمومی

### بعد از `wsl --shutdown` هیچ‌چیز کار نمی‌کند

داکر خودکار بالا نمی‌آید مگر systemd فعال باشد:

```bash
sudo service docker start
sudo docker ps          # کانتینر باید خودش Up شده باشد (restart policy)
```

برای فعال‌سازی دائمی، در `/etc/wsl.conf` اوبونتو:

```ini
[boot]
systemd=true
```

سپس در ویندوز: `wsl --shutdown` و بازکردن مجدد.

### Master Key را گم کردم

```bash
cat ~/.litellm/master_key.txt
```

### چطور وضعیت کلی را یکجا ببینم؟

```bash
sudo docker ps --filter name=litellm
sudo docker inspect -f '{{.State.Status}} | {{.HostConfig.RestartPolicy.Name}}' litellm
curl -s http://127.0.0.1:4000/health/liveliness
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $(cat ~/.litellm/master_key.txt)"
```

### اجرای دوبارهٔ اسکریپت امن است؟

بله — نصب مجدد (گزینهٔ `1`) اول کانتینر قبلی را حذف می‌کند و همه‌چیز را از نو و هماهنگ می‌سازد. کلیدهای API قبلی را هم **نگه می‌دارد**: فقط می‌پرسد «Keep these keys? [Y/n]» — با Enter همان‌ها حفظ و با `n` کلیدهای جدید پرسیده می‌شود. Master Key هم ثابت می‌ماند. حذف (گزینهٔ `2`) هم idempotent است.

</div>
