# Discord VPN Shop Bot

บอทเวอร์ชัน Discord ที่พอร์ตจาก Telegram bot เดิม โดยยังใช้ฐานข้อมูล SQLite และ 3x-ui API เดิม

## วิธีรัน

1. ติดตั้ง dependencies
```bash
pip install -r requirements.txt
```

2. ตั้งค่าไฟล์ `.env`
```env
DISCORD_TOKEN=ใส่โทเคนบอท Discord
ADMIN_IDS=123456789012345678,987654321098765432
XUI_URL=https://your-panel.example.com:2053/secretpath
XUI_API_TOKEN=ใส่ token จาก 3x-ui
AIS_INBOUND_ID=1
TRUE_INBOUND_ID=2
DB_PATH=/data/bot.db
TRUEMONEY_WALLET_PHONE=0xxxxxxxxx
```

3. เปิด Intent นี้ใน Discord Developer Portal
- Message Content Intent
- Server Members Intent แนะนำให้เปิด

4. รัน
```bash
python main.py
```

## คำสั่งหลัก

- `!start`
- `!mycredit`
- `!checkprice`
- `!addclient`
- `!freeclient`
- `!mycodes`
- `!addmycredit`
- `!entercode`

## คำสั่งแอดมิน

- `!addcredits @user 10`
- `!deletecredits @user 10`
- `!setprice 2`
- `!settingsmycredit`
- `!setangpaophone 0xxxxxxxxx`
- `!setangpaorate 1.5`
- `!checkangpaophone`
- `!toggleaddclient`
- `!buydm`
- `!nobuydm`
- `!openfreeclient`
- `!offfreeclient`
- `!freeclientlimit 1`
- `!freeclienttime 1`
- `!freeclientresettime midnight`
- `!resetfreeclientlimit @user`
- `!addcode`
- `!deletecode ชื่อโค้ด`
- `!checkcode`
- `!statuscode on`
- `!checkusercode ชื่อโค้ด`
- `!logbuy @user`
- `!logfree @user`
- `!logbuyall`
- `!logfreeall`

## หมายเหตุ

- คำสั่งย่อยส่วนใหญ่ใช้ข้อความโต้ตอบแบบทีละขั้นในห้องแชท
- ลิงก์/โค้ด VPN และเครดิตยังใช้ฐานข้อมูลเดิม
- ถ้าต้องการแปลงเป็น slash commands แบบแท้ ๆ ของ Discord เพิ่มได้ภายหลัง
