<div align="tight" dir="rtl">

# 🗑️ راهنمای حذف کامل (Uninstall)

---

## ۱. حذف از طریق منو

اسکریپت را اجرا کنید و گزینهٔ `2` را بزنید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)
```

```
   Enter your choice [1/2/q]: 2
```

خروجی موفق:

```
[INFO] === FULL UNINSTALL: starting ===
[INFO] Stopping and removing container 'litellm'...
[ OK ] Container removed.
[ OK ] Removed LiteLLM config folder: /home/<user>/.litellm
[ OK ] Removed OpenCode config: /mnt/c/Users/<Name>/.config/opencode/opencode.json

=================================================================
  UNINSTALL COMPLETED SUCCESSFULLY!
=================================================================
```

این کار **قابل تکرار** است؛ اگر چیزی برای حذف وجود نداشته باشد، به‌جای خطا فقط هشدار می‌دهد و با کد خروج ۰ تمام می‌شود.

---

## ۲. چه چیزی حذف می‌شود و چه چیزی می‌ماند؟

| مورد | وضعیت | مسیر |
|---|---|---|
| کانتینر `litellm` | ✅ حذف (stop + rm) | — |
| پوشهٔ کانفیگ لینوکس | ✅ حذف | `~/.litellm/` (شامل `config.yaml` و `master_key.txt`) |
| کانفیگ OpenCode ویندوز | ✅ حذف | `%USERPROFILE%\.config\opencode\opencode.json` |
| خودِ Docker | ❌ حفظ | — |
| میرورهای ایرانی | ❌ حفظ | `/etc/docker/daemon.json` |
| ایمیج LiteLLM (دانلودشده) | ❌ حفظ | برای نصب مجدد سریع |
| پوشهٔ `.config/opencode` (اگر فایل دیگری داشته باشد) | ❌ حفظ | فقط `opencode.json` پاک می‌شود |

---

## ۳. حذف دستی (اگر اسکریپت در دسترس نیست)

داخل WSL:

```bash
sudo docker stop litellm 2>/dev/null
sudo docker rm litellm 2>/dev/null
rm -rf ~/.litellm
```

در ویندوز (PowerShell یا Run):

```powershell
del "$env:USERPROFILE\.config\opencode\opencode.json"
```

---

## ۴. حذف کامل‌تر (اختیاری)

اگر می‌خواهید اثری از نصب باقی نماند:

```bash
# حذف ایمیج (حدود ۲ گیگابایت آزاد می‌شود)
sudo docker rmi ghcr.io/berriai/litellm:main-latest

# حذف میرورهای ایرانی (پوشهٔ /etc/docker را برمی‌گرداند به حالت قبل)
sudo rm -f /etc/docker/daemon.json
sudo service docker restart

# غیرفعال کردن استارت خودکار (اگر systemd دارید)
sudo systemctl disable docker.service
```

و در نهایت اگر خودِ داکر هم لازم ندارید:

```bash
sudo apt-get remove --purge -y docker.io
sudo apt-get autoremove -y
```

---

## ۵. نصب مجدد

بعد از Uninstall، برای نصب مجدد کافی است دوباره گزینهٔ `1` را اجرا کنید. چون ایمیج و داکر حفظ شده‌اند، نصب مجدد فقط چند ثانیه طول می‌کشد (بدون دانلود مجدد).

</div>
