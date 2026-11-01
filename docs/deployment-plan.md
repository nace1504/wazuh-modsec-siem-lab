# Kế Hoạch Triển Khai Chi Tiết & Checklist Vận Hành (Master Deployment Plan)

Tài liệu này cung cấp lộ trình kỹ thuật chuẩn hóa từ A đến Z phục vụ triển khai, vận hành và nghiệm thu hệ thống **Wazuh ModSecurity SIEM Lab**, áp dụng cho cả môi trường máy ảo nội bộ (Local Virtualization) và môi trường Cloud (VPS / AWS / DigitalOcean).

---

## 📋 BẢNG CHECKLIST TIẾN ĐỘ TỔNG THỂ (MASTER CHECKLIST)

### Giai đoạn 0: Thiết Lập Mạng Ảo & Khởi Tạo Máy Ảo Trên VMware
- [x] 0.1 Cấu hình Virtual Network Editor trên VMware (`VMnet8 NAT`: Subnet `192.168.1.0/24`, Gateway `192.168.1.2`, DHCP `192.168.1.100 - 192.168.1.200`).
- [x] 0.2 Khởi tạo **VM 1 (Attacker)**: Mở trực tiếp máy ảo đóng gói sẵn `kali-linux-2024.4-vmware-amd64.7z` (2 vCPU, 2-4GB RAM, Card `VMnet8`).
- [x] 0.3 Khởi tạo **VM 2 (Web Target & WAF)**: Cài đặt từ ISO trong thư mục `iso ubuntu 22.04.5` (2 vCPU, 4GB RAM, 30GB Disk, Card `VMnet8`).
- [x] 0.4 Khởi tạo **VM 3 (Wazuh AIO SIEM)**: Cài đặt từ ISO trong thư mục `iso ubuntu 22.04.5` (4 vCPU, 8GB RAM, 50GB Disk, Card `VMnet8`).
- [x] 0.5 Cấu hình IP tĩnh: VM 1 (`.10`), VM 2 (`.20`), VM 3 (`.30`).
- [x] 0.6 Đồng bộ thời gian qua NTP (`timedatectl set-ntp true`) trên cả 3 VM.
- [x] 0.7 **Chốt chặn 0:** Kiểm tra ma trận ping chéo 3 máy và kiểm tra ra Internet thành công.

### Giai đoạn 1: Khởi tạo Workspace & Quản trị Cấu hình
- [x] 1.1 Khởi tạo file biến môi trường `.env` từ `.env.example`.
- [x] 1.2 Cấu hình định tuyến địa chỉ IP (`WAZUH_MANAGER_IP`, `TARGET_IP`, `ATTACKER_IP`).
- [x] 1.3 Kiểm tra `.gitignore` bảo vệ thông tin nhạy cảm và file log.
- [x] 1.4 Kiểm tra phân quyền thực thi các bash script (`chmod +x scripts/*.sh`).

### Giai đoạn 2: Xây dựng Lớp WAF & Docker trên VM 2 (Web Target)
- [ ] 2.1 Tạo thư mục `/var/log/modsec` và cấp quyền ghi cho container (`chmod 755`, file `666`).
- [ ] 2.2 Kiểm tra file cấu hình WAF `modsec.conf` (Single-line JSON format, CRS v4 rules).
- [ ] 2.3 Khởi chạy cụm container qua Docker Compose (`modsec-waf` và `dvwa`).
- [ ] 2.4 Xác nhận mạng cô lập Docker bridge `target-net` (DVWA không mở port trực tiếp ra ngoài).
- [ ] 2.5 **Chốt chặn 1:** Kiểm thử cục bộ bằng `curl` kiểm tra mã `403` và xác thực JSON log qua `jq .`.

### Giai đoạn 3: Cấu hình Trung tâm SIEM & Phân tích trên VM 3 (Wazuh AIO)
- [ ] 3.1 Cài đặt Wazuh All-in-One trên VM 3.
- [ ] 3.2 Tối ưu hóa JVM Heap Memory cho Wazuh Indexer lên **4GB** (`-Xms4g -Xmx4g`).
- [ ] 3.3 Sao chép file custom rules `modsec_crs4_rules.xml` vào `/var/ossec/etc/rules/`.
- [ ] 3.4 Kiểm tra cú pháp rule bằng `wazuh-analysisd -t` và restart `wazuh-manager`.
- [ ] 3.5 Cài đặt Wazuh Agent trên VM 2 trỏ về VM 3 qua cổng TCP 1514 (tuyệt đối không dùng Syslog UDP 514).
- [ ] 3.6 Cấu hình directive `<localfile>` đọc file log JSON trên VM 2.
- [ ] 3.7 Triển khai script Active Response can thiệp chuỗi `DOCKER-USER` của iptables trên VM 2.
- [ ] 3.8 Khai báo `<command>` và `<active-response>` trên Wazuh Manager kích hoạt ở Rule 100110.
- [ ] 3.9 (Tùy chọn) Thiết lập tích hợp Webhook thông báo về Telegram Bot khi Alert Level $\ge 12$.

### Giai đoạn 4: Tự động hóa Scripting & Kiểm thử Tấn công
- [ ] 4.1 Cập nhật script `setup-vm2-agent.sh` tự động nạp biến từ `.env`.
- [ ] 4.2 Thực thi kịch bản `test-attacks.sh` từ VM 1 (Attacker):
  - [ ] Kiểm thử Baseline (HTTP 200).
  - [ ] Kiểm thử SQL Injection (CRS 942xxx -> HTTP 403, Alert Level 10).
  - [ ] Kiểm thử Cross-Site Scripting (CRS 941xxx -> HTTP 403, Alert Level 10).
  - [ ] Kiểm thử Path Traversal (CRS 930xxx -> HTTP 403, Alert Level 10).
  - [ ] Kiểm thử Remote Code Execution (CRS 932xxx -> HTTP 403, Alert Level 12).
  - [ ] Kiểm thử tần suất cao (Trigger Rule 100110 -> Level 14).
- [ ] 4.3 Xác thực Active Response: Kiểm tra iptables chuỗi `DOCKER-USER` đã drop IP VM 1.
- [ ] 4.4 Xác minh các sự kiện và Dashboard hiển thị đầy đủ trên Wazuh Dashboard Web UI.

### Giai đoạn 5: Sẵn sàng Triển khai Cloud (Production Ready)
- [ ] 5.1 Cấu hình Security Group / UFW trên Cloud (mở port 80, 443, 1514; đóng chặt port 9200, 55000).
- [ ] 5.2 Kiểm tra chứng chỉ SSL/TLS cho Wazuh Dashboard và Nginx Reverse Proxy.
- [ ] 5.3 Lập lịch tự động xoay vòng log (logrotate) cho `/var/log/modsec/modsec_audit.log`.

---

## 🚀 HƯỚNG DẪN THỰC THI CHI TIẾT TỪNG BƯỚC

### GIAI ĐOẠN 0: THIẾT LẬP MẠNG ẢO & KHỞI TẠO MÁY ẢO TRÊN VMWARE
> 📖 **Cẩm nang chi tiết từng cú click chuột và lệnh cấu hình:** Xem toàn bộ tại file [**`docs/phase0-vmware-setup.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/phase0-vmware-setup.md).

* **Bước 0.1:** Mở *VMware Virtual Network Editor* (Admin) $\rightarrow$ Cấu hình `VMnet8 (NAT)`: Subnet `192.168.1.0/24`, Gateway `192.168.1.2`, DHCP `192.168.1.100 - 192.168.1.200`.
* **Bước 0.2:** Tạo 3 máy ảo theo nguồn file sẵn có:
  * **VM 1 (Attacker):** Dùng `kali-linux-2024.4-vmware-amd64.7z` (Giải nén và mở file `.vmx` trực tiếp, 2 vCPU, 2-4GB RAM, Card `VMnet8`).
  * **VM 2 (Web Target & WAF):** Dùng ISO trong thư mục `iso ubuntu 22.04.5` (2 vCPU, 4GB RAM, 30GB Disk, Card `VMnet8`).
  * **VM 3 (Wazuh SIEM):** Dùng ISO trong thư mục `iso ubuntu 22.04.5` (4 vCPU, 8GB RAM, 50GB Disk, Card `VMnet8`).
* **Bước 0.3:** Cấu hình Static IP (VM 1: `.10`, VM 2: `.20`, VM 3: `.30`) và kiểm tra ma trận kết nối (Ping chéo & Internet).
* **Bước 0.4:** Đồng bộ thời gian qua NTP (`timedatectl set-ntp true`) trên cả 3 máy để bảo vệ chứng chỉ TLS của Wazuh.

---

### GIAI ĐOẠN 1: KHỞI TẠO WORKSPACE & BIẾN MÔI TRƯỜNG
> 📖 **Cẩm nang chi tiết từng bước (.env, Git Remote, SSH Passwordless, dos2unix):** Xem toàn bộ tại file [**`docs/phase1-workspace-env-setup.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/phase1-workspace-env-setup.md).

1. **Khởi tạo file cấu hình môi trường:**
   ```bash
   cp .env.example .env
   ```
2. **Chỉnh sửa các tham số thực tế:**
   ```ini
   DEPLOY_ENV=local                     # Hoặc "cloud"
   ATTACKER_IP=192.168.1.10             # IP máy tấn công (VM 1)
   TARGET_IP=192.168.1.20               # IP máy chủ WAF (VM 2)
   WAZUH_MANAGER_IP=192.168.1.30        # IP Wazuh Manager (VM 3)
   INDEXER_JAVA_HEAP=4g                 # Bộ nhớ Heap cho Indexer
   ```
3. **Phân quyền thực thi cho các script:**
   ```bash
   chmod +x scripts/*.sh
   ```

---

### GIAI ĐOẠN 2: XÂY DỰNG LỚP WAF & DOCKER TRÊN VM 2 (WEB TARGET)
> 📖 **Cẩm nang chi tiết từng bước (Docker Compose, ModSec CRS v4, JSON Log, curl tests):** Xem toàn bộ tại file [**`docs/phase2-waf-docker-setup.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/phase2-waf-docker-setup.md).

#### 1. Tạo thư mục chứa log trên Host OS:
```bash
sudo mkdir -p /var/log/modsec
sudo touch /var/log/modsec/modsec_audit.log
sudo chmod 755 /var/log/modsec
sudo chmod 666 /var/log/modsec/modsec_audit.log
```

#### 2. Khởi chạy cụm dịch vụ:
```bash
cd vm2-web-target
docker compose up -d --build
```

#### 3. Chốt chặn kiểm thử 1 (Verification Checkpoint 1):
```bash
# 1. Kiểm tra container hoạt động
docker compose ps

# 2. Kiểm tra truy cập bình thường (kỳ vọng 200 hoặc 302)
curl -I http://localhost/

# 3. Bắn payload kiểm thử SQLi (kỳ vọng 403 Forbidden)
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost/?id=1'%20OR%20'1'='1"

# 4. Xác thực định dạng JSON log (không được có lỗi cú pháp)
tail -n 1 /var/log/modsec/modsec_audit.log | jq .
```

---

### GIAI ĐOẠN 3: CẤU HÌNH TRUNG TÂM SIEM & PHÂN TÍCH TRÊN VM 3 (WAZUH AIO)

#### 1. Tối ưu hóa JVM Heap Memory cho Wazuh Indexer (4GB):
Mở file cấu hình JVM của Indexer:
```bash
sudo nano /etc/wazuh-indexer/jvm.options
```
Thêm/chỉnh sửa 2 dòng:
```properties
-Xms4g
-Xmx4g
```
Khởi động lại dịch vụ Indexer:
```bash
sudo systemctl restart wazuh-indexer
ps aux | grep java | grep -E "Xms4g|Xmx4g"
```

#### 2. Nạp Custom Rules cho ModSecurity CRS v4:
Sao chép bộ luật tùy biến vào thư mục luật của Wazuh Manager:
```bash
sudo cp vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml /var/ossec/etc/rules/
sudo chown wazuh:wazuh /var/ossec/etc/rules/modsec_crs4_rules.xml
sudo chmod 660 /var/ossec/etc/rules/modsec_crs4_rules.xml

# Kiểm tra cú pháp rule trước khi nạp
sudo /var/ossec/bin/wazuh-analysisd -t
sudo systemctl restart wazuh-manager
```

#### 3. Cấu hình Active Response cho chuỗi `DOCKER-USER` (VM 2 Agent):
> **Giải thích kỹ thuật:** Docker can thiệp vào iptables trước chuỗi `INPUT`. Muốn chặn request đến Docker container, bắt buộc phải chèn rule vào chuỗi `DOCKER-USER`.

Tạo script thực thi Active Response trên VM 2 tại `/var/ossec/active-response/bin/docker-firewall-drop`:
```bash
sudo tee /var/ossec/active-response/bin/docker-firewall-drop > /dev/null << 'EOF'
#!/bin/bash
# Wazuh Active Response script for Docker (DOCKER-USER chain)
ACTION=$1
USER=$2
IP=$3

if [ -z "$IP" ]; then
    read INPUT_JSON
    ACTION=$(echo "$INPUT_JSON" | jq -r '.command')
    IP=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.data.transaction.client_ip // .parameters.alert.srcip')
fi

if [ "$ACTION" = "add" ]; then
    /sbin/iptables -I DOCKER-USER -s "$IP" -j DROP
    logger -t wazuh-ar "Blocked IP $IP via DOCKER-USER chain"
elif [ "$ACTION" = "delete" ]; then
    /sbin/iptables -D DOCKER-USER -s "$IP" -j DROP
    logger -t wazuh-ar "Unblocked IP $IP from DOCKER-USER chain"
fi
EOF

sudo chmod 750 /var/ossec/active-response/bin/docker-firewall-drop
sudo chown root:wazuh /var/ossec/active-response/bin/docker-firewall-drop
```

Khai báo trên Wazuh Manager (VM 3) trong `/var/ossec/etc/ossec.conf`:
```xml
<command>
  <name>docker-firewall-drop</name>
  <executable>docker-firewall-drop</executable>
  <timeout_allowed>yes</timeout_allowed>
</command>

<active-response>
  <command>docker-firewall-drop</command>
  <location>local</location>
  <rules_id>100110</rules_id>
  <timeout>600</timeout>
</active-response>
```

---

### GIAI ĐOẠN 4: TỰ ĐỘNG HÓA SCRIPTING & KIỂM THỬ TẤN CÔNG

#### 1. Cài đặt và kết nối Agent tự động từ VM 2:
```bash
sudo bash scripts/setup-vm2-agent.sh
```

#### 2. Thực hiện tấn công từ máy Attacker (VM 1):
```bash
bash scripts/test-attacks.sh http://192.168.1.20
```

#### 3. Chốt chặn kiểm thử 2 (Verification Checkpoint 2):
1. **Kiểm tra iptables chuỗi DOCKER-USER trên VM 2:**
   ```bash
   sudo iptables -L DOCKER-USER -n -v
   ```
   *(Phải xuất hiện dòng `DROP all -- 192.168.1.10 0.0.0.0/0`)*
2. **Thử lại từ Attacker:**
   ```bash
   curl -I --connect-timeout 3 http://192.168.1.20/
   ```
   *(Kỳ vọng: Connection timed out)*
3. **Kiểm tra trên Wazuh Dashboard:**
   * Lọc `rule.groups: "modsecurity"`
   * Xem đầy đủ các Rule ID `100101`, `100102`, `100103`, `100104`, `100105`, `100110` được kích hoạt tương ứng.

---

### GIAI ĐOẠN 5: SẴN SÀNG TRIỂN KHAI CLOUD (PRODUCTION READY)

#### 1. Thiết lập Security Groups / Cloud Firewall:
* **VM 2 (Web Target):**
  * `Port 80 / 443 TCP`: Mở công khai `0.0.0.0/0`
  * `Port 22 TCP`: Chỉ cho phép IP quản trị (Admin IP)
* **VM 3 (Wazuh SIEM):**
  * `Port 1514 TCP`: Chỉ cho phép Public IP của VM 2 kết nối
  * `Port 1515 TCP`: Đăng ký Agent (chỉ mở khi đăng ký hoặc restrict theo IP VM 2)
  * `Port 443 TCP`: Truy cập Dashboard (chỉ Admin IP)
  * `Port 9200, 55000 TCP`: **Chặn hoàn toàn từ Internet**

#### 2. Cấu hình tự động Logrotate cho Audit Log:
Tạo file `/etc/logrotate.d/modsec` trên VM 2:
```text
/var/log/modsec/modsec_audit.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
```

