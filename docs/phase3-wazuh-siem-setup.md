# Hướng Dẫn Chi Tiết Giai Đoạn 3: Cấu Hình Trung Tâm SIEM & Phân Tích Trên VM 3 (Wazuh AIO)

Tài liệu này là cẩm nang kỹ thuật hướng dẫn chi tiết từng bước (Step-by-step) dành cho kỹ sư SOC/SIEM triển khai hệ thống giám sát an ninh tập trung: **Cài đặt Wazuh All-in-One trên VM 3 (`192.168.1.30`)**, tối ưu hóa bộ nhớ Heap 4GB cho Indexer, nạp bộ luật tùy biến **OWASP CRS v4**, kết nối **Wazuh Agent trên VM 2**, và kích hoạt cơ chế phản ứng tự động **Active Response** qua chuỗi tường lửa `DOCKER-USER`.

---

## 🗺️ 1. MÔ HÌNH KIẾN TRÚC TRUNG TÂM SIEM TẬP TRUNG

```
┌─────────────────────────────────────────────────────────────┐
│ VM 2: Web Target & WAF (192.168.1.20)                       │
│                                                             │
│   ModSecurity Audit Log ──> /var/log/modsec/modsec_audit.log│
│                                      │ (Single-line JSON)   │
│                                      ▼                      │
│   Wazuh Agent (Host Daemon) ─── <localfile> (format: json)  │
│         ▲                            │                      │
│         │ Nhận lệnh Active Response  │ TCP 1514 (AES-256)   │
│         │ (iptables DOCKER-USER)     ▼                      │
└─────────┼────────────────────────────┼──────────────────────┘
          │                            │
          │                            │ Kênh kết nối mã hóa
          │                            ▼
┌─────────┴───────────────────────────────────────────────────┐
│ VM 3: Wazuh All-In-One SIEM Server (192.168.1.30)           │
│                                                             │
│   [TCP 1514 / 1515]                                         │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Wazuh Manager (Core Engine)                         │   │
│   │ - Built-in JSON Decoder (Tự động giải mã)           │   │
│   │ - Custom Ruleset (modsec_crs4_rules.xml: 100100-110)│   │
│   │ - Active Response Engine                            │   │
│   └──────────────────────────┬──────────────────────────┘   │
│                              │                              │
│                              │ Ghi Alert qua cổng HTTPS 9200│
│                              ▼                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Wazuh Indexer (OpenSearch 2.x)                      │   │
│   │ - Java Heap Memory: Tối ưu 4GB (-Xms4g -Xmx4g)      │   │
│   │ - Lưu trữ & Đánh chỉ mục sự kiện theo thời gian thực │   │
│   └──────────────────────────┬──────────────────────────┘   │
│                              │                              │
│                              │ Truy vấn hiển thị            │
│                              ▼                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Wazuh Dashboard (Web UI - Cổng HTTPS 443)           │   │
│   │ - Giao diện trực quan hóa SOC Analyst               │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 2. MỤC TIÊU CỦA GIAI ĐOẠN 3

1. **Khởi dựng Wazuh All-in-One (AIO):** Cài đặt đầy đủ 3 thành phần (Manager, Indexer, Dashboard) trên hệ điều hành Ubuntu Server 22.04 LTS của VM 3.
2. **Tối ưu hóa hiệu năng Indexer (Heap 4GB):** Cấu hình `-Xms4g -Xmx4g` cho OpenSearch JVM để hệ thống không bị nghẽn I/O khi nhận log dồn dập.
3. **Nạp bộ luật tùy biến ModSecurity CRS v4:** Tích hợp bộ giải mã JSON có sẵn (`json_decoder`) để bắt mã lỗi `HTTP 403`, phân loại tấn công OWASP (SQLi, XSS, Path Traversal, RCE) theo chuẩn MITRE ATT&CK và PCI-DSS.
4. **Thu thập log chuẩn qua TCP 1514:** Cài đặt Wazuh Agent trên VM 2 kết nối an toàn về VM 3, cấu hình directive `<localfile>` đọc file log JSON (loại bỏ hoàn toàn rủi ro mất gói của Syslog UDP 514).
5. **Kích hoạt Active Response chuỗi `DOCKER-USER`:** Tự động ra lệnh cho VM 2 khóa IP kẻ tấn công vào chuỗi `DOCKER-USER` của iptables khi phát hiện hành vi tấn công lặp lại $\ge 4$ lần/60 giây.
6. **(Tùy chọn) Webhook Telegram:** Bắn thông báo khẩn cấp về điện thoại khi có sự cố nghiêm trọng (Alert Level $\ge 12$).

---

## 🚀 3. BƯỚC 1: CÀI ĐẶT WAZUH ALL-IN-ONE TRÊN VM 3 (`192.168.1.30`)

Đăng nhập vào VM 3 (`ssh admin@192.168.1.30` hoặc `ssh vm3-wazuh`):

### 1.1. Tải và chạy script cài đặt tự động chuẩn của Wazuh:
```bash
cd ~
curl -sO https://packages.wazuh.com/4.8/wazuh-install.sh
sudo bash wazuh-install.sh -a
```
*(Quá trình cài đặt tự động diễn ra trong khoảng 5 - 10 phút tùy tốc độ mạng)*.

---

### 1.2. Lưu trữ thông tin đăng nhập quan trọng:
Khi script chạy xong, terminal sẽ in ra bảng thông tin tài khoản đăng nhập Dashboard:
```text
The installation finished successfully.
User: admin
Password: <CHUỖI_MẬT_KHẨU_NGẪU_NHIÊN>
```
> [!IMPORTANT]
> **Hãy copy và lưu chuỗi mật khẩu này lại!** Mật khẩu cũng được lưu trữ an toàn trong file nén `wazuh-install-files.tar`. Bạn có thể xem lại bất cứ lúc nào bằng lệnh:
> ```bash
> sudo tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt | grep -E "admin"
> ```

---

### 1.3. Kiểm tra trạng thái hoạt động của cụm SIEM:
```bash
sudo systemctl status wazuh-manager wazuh-indexer wazuh-dashboard
```
*(Đảm bảo cả 3 dịch vụ đều ở trạng thái `active (running)`)*.

---

## ⚡ 4. BƯỚC 2: TỐI ƯU HÓA BỘ NHỚ 4GB HEAP CHO WAZUH INDEXER

Mặc định, Wazuh Indexer chỉ tự cấp khoảng 1GB - 2GB RAM. Đối với môi trường lab giả lập tấn công liên tục, ta cần nâng lên **4GB Heap**:

1. **Mở file cấu hình JVM của Indexer:**
   ```bash
   sudo nano /etc/wazuh-indexer/jvm.options
   ```

2. **Chỉnh sửa 2 dòng cấu hình bộ nhớ:**
   ```properties
   -Xms4g
   -Xmx4g
   ```
   *(Nhấn `Ctrl + O`, `Enter` để lưu, `Ctrl + X` để thoát)*.

3. **Khởi động lại Indexer để áp dụng:**
   ```bash
   sudo systemctl restart wazuh-indexer
   ```

4. **Xác thực cấu hình RAM thực tế:**
   ```bash
   ps aux | grep java | grep -E "Xms4g|Xmx4g"
   ```
   *(Nếu in ra dòng tiến trình Java chứa `-Xms4g -Xmx4g` là thành công)*.

---

## 📜 5. BƯỚC 3: NẠP CUSTOM RULES MODSECURITY CRS V4 TRÊN WAZUH MANAGER

File luật [`modsec_crs4_rules.xml`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml) đã được viết sẵn chuẩn hóa cho định dạng JSON log.

### 5.1. Sao chép bộ luật vào thư mục luật của Wazuh Manager:
Đảm bảo bạn đã clone repo về VM 3 (hoặc tạo file trực tiếp):

```bash
# 1. Copy file luật vào thư mục rules của Wazuh
sudo cp ~/wazuh-modsec-siem-lab/vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml /var/ossec/etc/rules/

# 2. Phân quyền chuẩn cho tiến trình wazuh
sudo chown wazuh:wazuh /var/ossec/etc/rules/modsec_crs4_rules.xml
sudo chmod 660 /var/ossec/etc/rules/modsec_crs4_rules.xml
```

---

### 5.2. Giải thích chi tiết các Rule ID trọng tâm:

| Rule ID | Alert Level | Điều kiện kích hoạt | Phân loại tấn công / MITRE ATT&CK |
| :---: | :---: | :--- | :--- |
| **`100100`** | **3** | Bất kỳ log nào có định dạng JSON và chứa trường `transaction.client_ip` | Base Rule tiếp nhận sự kiện WAF |
| **`100101`** | **7** | Mã phản hồi HTTP là `403` (`transaction.response.http_code == 403`) | Request bị WAF chặn đứng (**T1190**) |
| **`100102`** | **10** | Vi phạm luật SQL Injection (CRS 942xxx) | SQL Injection (**T1190**, PCI-DSS 6.5.1) |
| **`100103`** | **10** | Vi phạm luật XSS (CRS 941xxx) | Cross-Site Scripting (**T1059.007**, PCI-DSS 6.5.7) |
| **`100104`** | **10** | Vi phạm luật Path Traversal / LFI (CRS 930xxx) | File Inclusion / Path Traversal (**T1083**) |
| **`100105`** | **12** | Vi phạm luật Remote Code Execution (CRS 932xxx) | Command Injection / RCE (**T1059**) |
| **`100110`** | **14** | Cùng 1 IP vi phạm từ 4 lần trong vòng 60 giây (`frequency="4" timeframe="60"`) | **Kích hoạt Active Response (Chặn IP)** |

---

### 5.3. Kiểm tra cú pháp và nạp luật mới:
```bash
# Kiểm tra tính hợp lệ của toàn bộ ruleset
sudo /var/ossec/bin/wazuh-analysisd -t
```
* **Kết quả kỳ vọng:** In ra thông báo kết thúc không có lỗi cú pháp.
* Sau đó khởi động lại Manager:
  ```bash
  sudo systemctl restart wazuh-manager
  ```

---

## 🤖 6. BƯỚC 4: CÀI ĐẶT & ĐĂNG KÝ WAZUH AGENT TRÊN VM 2 (`192.168.1.20`)

Đăng nhập vào máy ảo **VM 2** (`ssh admin@192.168.1.20`):

### 6.1. Thực thi script cài đặt tự động:
Tại thư mục repo trên VM 2, chạy script [`setup-vm2-agent.sh`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/scripts/setup-vm2-agent.sh):

```bash
cd ~/wazuh-modsec-siem-lab
sudo bash scripts/setup-vm2-agent.sh 192.168.1.30 vm2-web-target 4.8.2-1
```

*Script sẽ tự động:*
1. Thêm kho phần mềm (GPG Key & Repository) chính thức của Wazuh.
2. Cài đặt package `wazuh-agent`.
3. Cập nhật địa chỉ Manager `<address>192.168.1.30</address>` trong `/var/ossec/etc/ossec.conf`.
4. Gọi lệnh `agent-auth` đăng ký nhận khóa mã hóa (`client.keys`).
5. Tự động chèn block cấu hình đọc file log JSON vào `/var/ossec/etc/ossec.conf`:
   ```xml
   <localfile>
     <log_format>json</log_format>
     <location>/var/log/modsec/modsec_audit.log</location>
   </localfile>
   ```
6. Kích hoạt và bật dịch vụ `wazuh-agent`.

---

### 6.2. Xác thực và đăng ký bổ sung qua `agent-auth` (Bắt buộc nếu chưa nhận key):
> [!IMPORTANT]
> **Cơ chế xác thực của Wazuh Agent:**
> Để Agent có thể mã hóa và gửi dữ liệu qua cổng TCP 1514, Agent bắt buộc phải có khóa bí mật được lưu trong `/var/ossec/etc/client.keys`. Khóa này được cấp qua kênh đăng ký TCP 1515 bởi lệnh `agent-auth`.

Nếu kiểm tra file key chưa có hoặc Agent chưa kết nối, chạy lệnh đăng ký trực tiếp trên VM 2:
```bash
sudo /var/ossec/bin/agent-auth -m 192.168.1.30 -A vm2-web-target
```
* **Kết quả kỳ vọng:** In ra dòng `INFO: Valid key created. Closing connection.`
* Sau đó khởi động lại Agent:
  ```bash
  sudo systemctl restart wazuh-agent
  sudo systemctl status wazuh-agent
  ```

---

### 6.3. Xác nhận kết nối Agent từ VM 3 (Wazuh Manager):
Quay lại terminal của **VM 3**, chạy lệnh:
```bash
sudo /var/ossec/bin/agent_control -l
```
**Kết quả kỳ vọng:**
```text
Wazuh agent_control. List of available agents:
   ID: 000, Name: vm3-wazuh-server (server), IP: 127.0.0.1, Active/Local
   ID: 001, Name: vm2-web-target, IP: any, Active
```
*(Agent `vm2-web-target` hiển thị trạng thái **Active** là kết nối thành công 100%)*!

---

## 🛡️ 7. BƯỚC 5: THIẾT LẬP ACTIVE RESPONSE CHO CHUỖI `DOCKER-USER`

> [!CAUTION]
> **Điểm bẫy kỹ thuật kinh điển giữa Docker và iptables:**
> Script `firewall-drop` mặc định của Wazuh chèn rule chặn vào chuỗi `INPUT` (`iptables -I INPUT -s <IP> -j DROP`).
> Tuy nhiên, với các ứng dụng chạy trong Docker Container có mở cổng (như cổng 80 của Nginx WAF), nhân Linux sẽ chuyển tiếp gói tin từ bảng NAT `PREROUTING` thẳng vào chuỗi `FORWARD`, **hoàn toàn bỏ qua chuỗi `INPUT`**!
> Nếu chặn ở chuỗi `INPUT`, kẻ tấn công vẫn truy cập được vào WAF bình thường. Do đó, bắt buộc phải viết script Active Response chèn lệnh drop vào chuỗi **`DOCKER-USER`**!

---

### 7.1. Tạo script Active Response trên VM 2 (Agent Host):
Trên VM 2, tạo file script thực thi:
```bash
sudo tee /var/ossec/active-response/bin/docker-firewall-drop > /dev/null << 'EOF'
#!/bin/bash
# =============================================================================
# Custom Wazuh Active Response for Docker Environments (DOCKER-USER chain)
# =============================================================================

ACTION=$1
USER=$2
IP=$3

# Hỗ trợ đọc JSON payload nếu Wazuh gọi qua chuẩn mới
if [ -z "$IP" ]; then
    read -r INPUT_JSON
    ACTION=$(echo "$INPUT_JSON" | jq -r '.command // empty')
    IP=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.transaction.client_ip // .parameters.alert.srcip // empty')
fi

# Kiểm tra địa chỉ IP hợp lệ
if [ -z "$IP" ] || [ "$IP" = "null" ]; then
    logger -t wazuh-ar "[DOCKER-USER] Error: Missing or invalid IP"
    exit 1
fi

if [ "$ACTION" = "add" ]; then
    # Kiểm tra xem rule đã tồn tại chưa để tránh trùng lặp
    if ! /sbin/iptables -C DOCKER-USER -s "$IP" -j DROP 2>/dev/null; then
        /sbin/iptables -I DOCKER-USER -s "$IP" -j DROP
        logger -t wazuh-ar "[DOCKER-USER] Successfully BLOCKED attack IP: $IP"
    fi
elif [ "$ACTION" = "delete" ]; then
    /sbin/iptables -D DOCKER-USER -s "$IP" -j DROP 2>/dev/null
    logger -t wazuh-ar "[DOCKER-USER] Successfully UNBLOCKED IP: $IP"
fi
EOF

# Cấp quyền thực thi an toàn cho tiến trình wazuh
sudo chmod 750 /var/ossec/active-response/bin/docker-firewall-drop
sudo chown root:wazuh /var/ossec/active-response/bin/docker-firewall-drop
```

---

### 7.2. Khai báo Command & Active Response trên VM 3 (Wazuh Manager):
Trên VM 3, mở file cấu hình quản trị:
```bash
sudo nano /var/ossec/etc/ossec.conf
```
Tìm đến trước thẻ đóng `</ossec_config>` ở cuối file, chèn vào đoạn cấu hình sau:

```xml
  <!-- 1. Định nghĩa lệnh gọi script docker-firewall-drop -->
  <command>
    <name>docker-firewall-drop</name>
    <executable>docker-firewall-drop</executable>
    <timeout_allowed>yes</timeout_allowed>
  </command>

  <!-- 2. Kích hoạt Active Response khi Rule 100110 nổ -->
  <active-response>
    <command>docker-firewall-drop</command>
    <location>local</location>
    <rules_id>100110</rules_id>
    <timeout>600</timeout> <!-- Khóa IP trong vòng 10 phút (600 giây) -->
  </active-response>
```

Khởi động lại Wazuh Manager để nạp cấu hình:
```bash
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
```

---

## 📱 8. BƯỚC 6: TÍCH HỢP CẢNH BÁO TELEGRAM WEBHOOK (TÙY CHỌN)

Để nhận cảnh báo tức thời trên điện thoại khi có sự cố cấp độ cao (Level $\ge 12$ hoặc kích hoạt Active Response):

### 8.1. Khởi tạo Telegram Bot & Lấy Chat ID:
1. Mở ứng dụng Telegram, tìm bot **`@BotFather`** $\rightarrow$ Gõ `/newbot` để tạo bot và lấy `BOT_TOKEN`.
2. Tìm bot **`@userinfobot`** $\rightarrow$ Gõ `/start` để lấy `CHAT_ID` của bạn.

---

### 8.2. Tạo script Python gửi tin nhắn trên VM 3:
Tạo file `/var/ossec/integrations/custom-telegram.py`:
```bash
sudo tee /var/ossec/integrations/custom-telegram.py > /dev/null << 'EOF'
#!/usr/bin/env python3
import sys
import json
import requests

# Nhận đường dẫn file alert từ Wazuh
alert_file = sys.argv[1]
hook_url = sys.argv[3]

with open(alert_file) as f:
    alert = json.load(f)

# Trích xuất thông tin trọng yếu
rule_id = alert.get("rule", {}).get("id", "N/A")
level = alert.get("rule", {}).get("level", 0)
description = alert.get("rule", {}).get("description", "Security Alert")
src_ip = alert.get("data", {}).get("transaction", {}).get("client_ip", "Unknown")
agent_name = alert.get("agent", {}).get("name", "Unknown")

message = (
    f"🚨 *[WAZUH SIEM INCIDENT ALERT]*\n"
    f"• *Rule ID:* `{rule_id}` (Level {level})\n"
    f"• *Description:* {description}\n"
    f"• *Attacker IP:* `{src_ip}`\n"
    f"• *Target Agent:* `{agent_name}`\n"
    f"• *Mitigation:* Active Response DOCKER-USER Triggered"
)

# Gửi sang Telegram API
payload = {
    "text": message,
    "parse_mode": "Markdown"
}
requests.post(hook_url, json=payload, timeout=10)
EOF

sudo chmod 750 /var/ossec/integrations/custom-telegram.py
sudo chown root:wazuh /var/ossec/integrations/custom-telegram.py
```

---

### 8.3. Khai báo thẻ `<integration>` trong `ossec.conf` trên VM 3:
Trong `/var/ossec/etc/ossec.conf`:
```xml
  <integration>
    <name>custom-telegram.py</name>
    <hook_url>https://api.telegram.org/bot<TOKEN_CỦA_BẠN>/sendMessage?chat_id=<CHAT_ID_CỦA_BẠN></hook_url>
    <level>12</level>
    <alert_format>json</alert_format>
  </integration>
```
Restart Manager: `sudo systemctl restart wazuh-manager`.

---

## 🧪 9. BƯỚC 7: NGHIỆM THU CHỐT CHẶN GIAI ĐOẠN 3 (CHECKPOINT 3)

### 9.1. Test phát hiện tấn công từ VM 2:
Trên VM 2, gửi một payload SQLi thử nghiệm:
```bash
curl "http://localhost/?id=1'%20OR%201=1--"
```

### 9.2. Kiểm tra log nhận diện trên VM 3:
Trên VM 3, theo dõi file log cảnh báo thời gian thực:
```bash
sudo tail -f /var/ossec/logs/alerts/alerts.json | grep -E "100102|modsecurity"
```
* **Kỳ vọng:** Xuất hiện ngay lập tức bản ghi JSON chứa `rule.id: 100102`, `rule.description: "ModSecurity CRS v4: SQL Injection Attack Detected and Blocked"`.

---

### 9.3. Đăng nhập giao diện Web Wazuh Dashboard:
1. Mở trình duyệt trên máy thật Windows: **`https://192.168.1.30`**
2. Cảnh báo SSL: Nhấn **Advanced** $\rightarrow$ **Proceed to 192.168.1.30 (unsafe)**.
3. Đăng nhập bằng tài khoản:
   * **Username:** `admin`
   * **Password:** *(Mật khẩu đã lưu ở Bước 1.2)*
4. Điều hướng vào menu **Security events**:
   * Tại thanh tìm kiếm gõ: `rule.groups: "modsecurity"`
   * **Kết quả:** Hiển thị trực quan toàn bộ biểu đồ tấn công, Top Rule IDs kích hoạt và danh sách IP nguồn!

---

## ✅ 10. BẢNG CHECKLIST NGHIỆM THU GIAI ĐOẠN 3

- [ ] 3.1 Wazuh All-in-One cài đặt thành công, cả 3 dịch vụ `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` đều `active`.
- [ ] 3.2 Java Heap của Wazuh Indexer đã được nâng lên **4GB** (`-Xms4g -Xmx4g`).
- [ ] 3.3 File `modsec_crs4_rules.xml` đã được copy vào `/var/ossec/etc/rules/` và kiểm tra `wazuh-analysisd -t` thành công.
- [ ] 3.4 Wazuh Agent trên VM 2 đã cài đặt và hiển thị trạng thái **Active** trên VM 3 (`agent_control -l`).
- [ ] 3.5 File `/var/ossec/etc/ossec.conf` trên VM 2 đã có block `<localfile>` đọc file log JSON.
- [ ] 3.6 Script `docker-firewall-drop` đã được tạo trên VM 2 và khai báo `<active-response>` trên VM 3.
- [ ] 3.7 Đăng nhập thành công giao diện Web Wazuh Dashboard tại `https://192.168.1.30`.

---

## 🎯 KẾT LUẬN GIAI ĐOẠN 3
Hệ thống phòng lab SOC/SIEM giờ đây đã hoàn chỉnh toàn bộ hạ tầng cốt lõi: WAF ModSecurity CRS v4 thu thập log, Wazuh Agent chuyển tiếp mã hóa qua TCP 1514, và Wazuh Manager/Indexer phân tích đánh chỉ mục theo thời gian thực.

👉 Bạn đã sẵn sàng để chuyển sang **Giai đoạn 4: Tự động hóa Scripting & Kiểm thử Tấn công từ máy VM 1 Attacker (Kali Linux)**!

