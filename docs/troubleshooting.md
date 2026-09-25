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

### `docker pull` خطای 403 یا `toomanyrequests` می‌دهد

علت: تحریم داکرهاب. اسکریپت ایمیج را از `ghcr.io` می‌گیرد که معمولاً باز است؛ اما اگر باز هم خطا دادید:

```bash
# بررسی دسترسی
curl -I https://ghcr.io/v2/
# مشاهدهٔ میرورهای فعال
cat /etc/docker/daemon.json
sudo service docker restart
```

اگر هنوز جواب نداد، یک VPN روی **ویندوز** بزنید (WSL ترافیک را از ویندوز رد می‌کند) و دوباره گزینهٔ `1` را اجرا کنید.

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

بله — نصب مجدد (گزینهٔ `1`) اول کانتینر قبلی را حذف می‌کند و همه‌چیز را از نو و هماهنگ می‌سازد. حذف (گزینهٔ `2`) هم idempotent است.

</div>
