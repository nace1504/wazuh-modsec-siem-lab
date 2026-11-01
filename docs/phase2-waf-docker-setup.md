# Hướng Dẫn Chi Tiết Giai Đoạn 2: Xây Dựng Lớp WAF & Docker Trên VM 2 (Web Target)

Tài liệu này là cẩm nang kỹ thuật hướng dẫn chi tiết từng bước (Step-by-step) dành cho kỹ sư triển khai thiết lập cụm container bảo vệ ứng dụng Web: **Nginx Reverse Proxy tích hợp WAF ModSecurity v3 (OWASP Core Rule Set v4)** và ứng dụng mục tiêu **DVWA** trên máy chủ **VM 2 (`192.168.1.20`)**.

---

## 🗺️ 1. MÔ HÌNH BẢO VỆ PHÂN TẦNG TẠI VM 2 (DEFENSE-IN-DEPTH)

```
[Attacker / Client: 192.168.1.10]
              │
              │ HTTP Request (Cổng 80)
              ▼
┌─────────────────────────────────────────────────────────────┐
│ VM 2 Host OS (Ubuntu Server 22.04 LTS - 192.168.1.20)       │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Docker Bridge Network: target-net                   │   │
│   │                                                     │   │
│   │   ┌───────────────────────────┐                     │   │
│   │   │ Container: modsec-waf     │ (Mở cổng 80:80)     │   │
│   │   │ - Nginx Reverse Proxy     │                     │   │
│   │   │ - ModSecurity v3 Engine   │                     │   │
│   │   │ - OWASP CRS v4 Ruleset    │                     │   │
│   │   └─────────────┬─────────────┘                     │   │
│   │                 │ (Proxy Pass - Chỉ traffic an toàn)│   │
│   │                 ▼                                   │   │
│   │   ┌───────────────────────────┐                     │   │
│   │   │ Container: dvwa-app       │ (Không mở port host)│   │
│   │   │ - Backend Apache + PHP    │                     │   │
│   │   │ - CSDL MariaDB/MySQL      │                     │   │
│   │   └───────────────────────────┘                     │   │
│   └─────────────────┼───────────────────────────────────┘   │
│                     │                                       │
│                     │ Bind-mount Volume (Single-line JSON)  │
│                     ▼                                       │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Host File: /var/log/modsec/modsec_audit.log         │   │
│   └─────────────────┬───────────────────────────────────┘   │
│                     │                                       │
│                     │ Đọc theo thời gian thực (&lt;localfile&gt;)  │
│                     ▼                                       │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Wazuh Agent (Host Daemon) ──[TCP 1514]──> [VM 3]   │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 2. MỤC TIÊU CỦA GIAI ĐOẠN 2

1. **Cô lập ứng dụng lõi (Zero Exposed Backend):** Container DVWA chỉ lắng nghe trong mạng Docker nội bộ (`target-net`), không mở bất kỳ cổng nào ra máy host. Toàn bộ lưu lượng truy cập bắt buộc phải đi qua lớp kiểm duyệt WAF.
2. **Kích hoạt lá chắn OWASP CRS v4:** Tích hợp bộ luật mới nhất **OWASP Core Rule Set (CRS) v4** ở chế độ chặn đứng (`SecRuleEngine On`), trả về mã `HTTP 403 Forbidden` khi phát hiện dấu hiệu tấn công.
3. **Chuẩn hóa Audit Log Single-line JSON:** Xuất toàn bộ thông tin kiểm toán bảo mật dưới định dạng JSON trên đúng một dòng duy nhất ra file trên Host OS `/var/log/modsec/modsec_audit.log`.
4. **Nghiệm thu chốt chặn 2 (Checkpoint 2):** Kiểm thử bắn payload trực tiếp trên VM 2 bằng lệnh `curl` và dùng `jq` để xác thực log JSON nguyên vẹn, sẵn sàng cho Wazuh Agent đọc ở Giai đoạn 3.

---

## 📁 3. CẤU TRÚC THƯ MỤC CỦA VM 2 TRONG REPO

```plaintext
vm2-web-target/
├── docker-compose.yml             # Khởi chạy cụm dịch vụ ModSec + DVWA
└── docker/
    ├── modsecurity/
    │   ├── Dockerfile             # Base image owasp/modsecurity-crs:nginx-alpine (CRS v4)
    │   ├── conf/
    │   │   ├── nginx.conf         # Cấu hình Reverse proxy trỏ về dvwa:80
    │   │   └── modsec.conf        # Bật WAF & cấu hình xuất log Single-line JSON
    │   └── owasp-crs/             # Thư mục luật CRS v4
    └── dvwa/
        └── init.sql               # Script khởi tạo CSDL mẫu (users, guestbook)
```

---

## 🛠️ 4. BƯỚC 1: CHUẨN BỊ MÔI TRƯỜNG & PHÂN QUYỀN LOG TRÊN HOST VM 2

> [!IMPORTANT]
> **Điểm mấu chốt về quyền ghi (Permissions):**
> Container Nginx/ModSecurity chạy với quyền người dùng không đặc quyền (`nginx` hoặc `nobody`). Nếu thư mục mount trên Host OS không được mở quyền ghi, ModSecurity sẽ ghi đè thất bại và im lặng không sinh log kiểm toán.

Đăng nhập vào VM 2 (`ssh admin@192.168.1.20` hoặc `ssh vm2-target`):

```bash
# 1. Tạo thư mục chứa log kiểm toán của ModSecurity trên Host OS
sudo mkdir -p /var/log/modsec

# 2. Tạo sẵn file log rỗng
sudo touch /var/log/modsec/modsec_audit.log

# 3. Phân quyền thư mục và file để Docker container có quyền ghi vào Host
sudo chmod 755 /var/log/modsec
sudo chmod 666 /var/log/modsec/modsec_audit.log

# 4. Kiểm tra lại quyền hạn
ls -ld /var/log/modsec
ls -l /var/log/modsec/modsec_audit.log
```
*(Kết quả file `modsec_audit.log` phải có quyền `-rw-rw-rw-`)*.

---

## 🔍 5. BƯỚC 2: PHÂN TÍCH CẤU HÌNH WAF & REVERSE PROXY

### 5.1. File cấu hình WAF lõi ([`docker/modsecurity/conf/modsec.conf`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/vm2-web-target/docker/modsecurity/conf/modsec.conf))
Các chỉ thị kỹ thuật quyết định sự thành bại của SIEM:
* **`SecRuleEngine On`:** Bật chế độ phòng thủ chủ động (Chặn & Ghi log). Nếu để `DetectionOnly` thì WAF chỉ ghi log mà không chặn.
* **`SecAuditLogFormat JSON`:** **Cực kỳ quan trọng**. Ép ModSecurity ghi dữ liệu dạng Single-line JSON thay vì định dạng Native nhiều phần ngắt dòng truyền thống.
* **`SecAuditLogRelevantStatus "^(?:5|4(?!04))"`:** Chỉ ghi nhận các request bị chặn (mã 4xx, trừ 404 để lọc nhiễu) hoặc lỗi máy chủ (mã 5xx).
* **`SecAuditLog /var/log/modsec/modsec_audit.log`:** Đường dẫn file log bên trong container (được map ra host).
* **`SecDefaultAction "phase:1,log,auditlog,deny,status:403"`:** Hành động mặc định khi vi phạm luật là chặn đứng với mã HTTP 403.

---

### 5.2. File cấu hình Reverse Proxy ([`docker/modsecurity/conf/nginx.conf`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/vm2-web-target/docker/modsecurity/conf/nginx.conf))
* **Bật ModSecurity trong Nginx:**
  ```nginx
  modsecurity on;
  modsecurity_rules_file /etc/nginx/modsec/modsec.conf;
  ```
* **Chuyển tiếp lưu lượng an toàn đến DVWA backend:**
  ```nginx
  upstream dvwa_backend {
      server dvwa:80;
  }
  location / {
      proxy_pass http://dvwa_backend;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```

---

## 🚀 6. BƯỚC 3: KHỞI CHẠY CỤM CONTAINER DOCKER

Thực hiện trên máy ảo VM 2:

```bash
# 1. Điều hướng vào thư mục vm2-web-target
cd ~/wazuh-modsec-siem-lab/vm2-web-target

# 2. Khởi chạy và build lại image mới nhất
docker compose up -d --build
```

### Kiểm tra trạng thái vận hành của cụm container:
```bash
docker compose ps
```
**Kết quả kỳ vọng (STATUS phải là UP):**
```text
NAME         IMAGE                                 COMMAND                  SERVICE      CREATED          STATUS          PORTS
dvwa-app     vulnerables/web-dvwa:latest           "/docker-entrypoint.…"   dvwa         10 seconds ago   Up 9 seconds    80/tcp
modsec-waf   vm2-web-target-modsec-waf             "/docker-entrypoint.…"   modsec-waf   10 seconds ago   Up 9 seconds    0.0.0.0:80->80/tcp, :::80->80/tcp
```

### Kiểm tra log khởi động của ModSecurity:
```bash
docker compose logs modsec-waf | head -n 30
```
*(Đảm bảo không xuất hiện dòng cảnh báo cú pháp cấu hình `[emerg]` hoặc `[error]`)*.

---

## 🧪 7. BƯỚC 4: KỊCH BẢN KIỂM THỬ CỤC BỘ & NGHIỆM THU (CHECKPOINT 2)

Thực hiện các lệnh kiểm thử sau ngay trên terminal của VM 2:

### 7.1. Test 1: Kiểm tra lưu lượng thông thường (Clean Request)
Gửi một request hợp lệ vào trang chủ DVWA:
```bash
curl -I http://localhost/
```
* **Kết quả kỳ vọng:** Trả về mã **`HTTP/1.1 200 OK`** hoặc **`HTTP/1.1 302 Found`** (chuyển hướng sang `login.php`). Chứng minh Nginx đã chuyển tiếp thành công đến DVWA backend.

---

### 7.2. Test 2: Bắn payload SQL Injection (SQLi)
Gửi payload khai thác vượt qua xác thực:
```bash
curl -s -o /dev/null -w "HTTP Code: %{http_code}\n" "http://localhost/?id=1'%20OR%20'1'='1"
```
* **Kết quả kỳ vọng:** **`HTTP Code: 403`** (Đã bị ModSecurity chặn đứng!).

---

### 7.3. Test 3: Bắn payload Cross-Site Scripting (XSS)
Gửi payload chứa thẻ script độc hại:
```bash
curl -s -o /dev/null -w "HTTP Code: %{http_code}\n" "http://localhost/?search=%3Cscript%3Ealert('XSS')%3C/script%3E"
```
* **Kết quả kỳ vọng:** **`HTTP Code: 403`**.

---

### 7.4. Test 4: Bắn payload Path Traversal / LFI
Thử nghiệm đọc file nhạy cảm `/etc/passwd`:
```bash
curl -s -o /dev/null -w "HTTP Code: %{http_code}\n" "http://localhost/?page=../../../../etc/passwd"
```
* **Kết quả kỳ vọng:** **`HTTP Code: 403`**.

---

### 7.5. Test 5: Xác thực tính toàn vẹn của Audit Log JSON
Kiểm tra dòng log mới nhất được ghi ra Host OS:
```bash
tail -n 1 /var/log/modsec/modsec_audit.log | jq .
```

* **Xác thực cấu trúc JSON:**
  1. Lệnh `jq .` phải định dạng đẹp (pretty-print) chuỗi JSON mà **không báo lỗi cú pháp** `parse error`.
  2. Trường `transaction.client_ip` chứa IP nguồn của client (`127.0.0.1` hoặc `192.168.1.x`).
  3. Trường `transaction.response.http_code` có giá trị `403`.
  4. Mảng `transaction.messages` chứa thông tin rule vi phạm của OWASP CRS (ví dụ: `SQL Injection Attack Detected via libinjection`, Rule ID `942100`).

---

### 7.6. Test 6: Kiểm tra giao diện Web trực quan từ máy Host (Windows)
1. Mở trình duyệt web (Google Chrome hoặc MS Edge) trên máy tính thật Windows.
2. Truy cập vào địa chỉ: **`http://192.168.1.20`**.
3. **Kết quả:** Giao diện đăng nhập của **DVWA (Damn Vulnerable Web Application)** xuất hiện mượt mà.
4. Thử chèn payload vào thanh địa chỉ:
   `http://192.168.1.20/?id=1' OR 1=1--`
5. **Kết quả:** Trình duyệt hiển thị ngay lập tức màn hình **403 Forbidden - Request blocked by ModSecurity WAF**!

---

## 🔧 8. HƯỚNG DẪN XỬ LÝ SỰ CỐ THƯỜNG GẶP (TROUBLESHOOTING)

| Hiện tượng lỗi | Nguyên nhân | Cách khắc phục |
| :--- | :--- | :--- |
| `Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:80: listen tcp 0.0.0.0:80: bind: address already in use` | Máy VM 2 đã có dịch vụ Apache/Nginx cài sẵn trên Host OS đang chiếm cổng 80. | Chạy lệnh tắt dịch vụ trên host: `sudo systemctl stop nginx apache2 && sudo systemctl disable nginx apache2` rồi chạy lại `docker compose up -d`. |
| Bắn payload trả về `403` nhưng file `/var/log/modsec/modsec_audit.log` dung lượng vẫn là 0 byte. | Lỗi phân quyền ghi file trên Host OS. | Chạy lệnh: `sudo chmod 755 /var/log/modsec && sudo chmod 666 /var/log/modsec/modsec_audit.log` và restart container: `docker compose restart modsec-waf`. |
| Truy cập `http://192.168.1.20` báo `502 Bad Gateway`. | Container DVWA chưa khởi động xong hoặc Nginx không phân giải được tên miền nội bộ `dvwa`. | Kiểm tra container DVWA: `docker compose logs dvwa`. Đảm bảo cả 2 container đều nằm trong network `target-net`. |
| Lệnh `tail -n 1 ... | jq .` báo lỗi `parse error: Invalid numeric literal`. | Log bị ghi ở dạng Native Multi-line thay vì Single-line JSON. | Kiểm tra file `docker/modsecurity/conf/modsec.conf`, đảm bảo có dòng `SecAuditLogFormat JSON`. Sau đó rebuild container: `docker compose up -d --build`. |

---

## ✅ 9. BẢNG CHECKLIST NGHIỆM THU GIAI ĐOẠN 2

- [ ] 2.1 Thư mục `/var/log/modsec` đã được tạo trên VM 2 với quyền `chmod 755`, file `modsec_audit.log` quyền `chmod 666`.
- [ ] 2.2 Cả 2 container `modsec-waf` và `dvwa-app` đều ở trạng thái `Up` khi kiểm tra qua `docker compose ps`.
- [ ] 2.3 Truy cập URL sạch trả về `HTTP 200/302`.
- [ ] 2.4 Payload SQLi, XSS, Path Traversal đều bị chặn với mã `HTTP 403 Forbidden`.
- [ ] 2.5 File `/var/log/modsec/modsec_audit.log` tăng dung lượng và parse thành công qua lệnh `jq .`.
- [ ] 2.6 Đã truy cập thành công giao diện DVWA và test mã lỗi 403 từ trình duyệt máy Host Windows.

---

## 🎯 KẾT LUẬN GIAI ĐOẠN 2
Khi hoàn thành toàn bộ checklist trên, lớp phòng thủ WAF ModSecurity CRS v4 trên VM 2 đã vận hành hoàn hảo và liên tục sinh ra nguồn dữ liệu kiểm toán JSON chất lượng cao.

👉 Tiếp theo, bạn có thể chuyển sang **Giai đoạn 3: Cấu hình Trung tâm SIEM & Phân tích trên VM 3 (Wazuh AIO)** để bắt đầu thiết lập Agent và bộ phân tích sự kiện an ninh tập trung!

