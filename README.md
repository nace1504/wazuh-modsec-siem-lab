# Wazuh ModSecurity SIEM Lab

Dự án triển khai mô hình phòng lab SOC / SIEM chuẩn công nghiệp giám sát ứng dụng Web, tích hợp giữa **Wazuh SIEM**, **WAF ModSecurity v3 (OWASP Core Rule Set v4)** và môi trường ứng dụng thử nghiệm **DVWA**.

---

## 📁 Cấu Trúc Thư Mục Dự Án (Repository Structure)

```plaintext
.
├── README.md                          # Hướng dẫn tổng quan, quy hoạch mạng và cách vận hành lab
├── docs/
│   └── architecture.md                # Tài liệu kiến trúc hệ thống chuẩn hóa
├── vm2-web-target/                    # Phân vùng VM 2: Web Server & WAF (Docker Host)
│   ├── docker-compose.yml             # Quản lý Nginx/ModSecurity, DVWA và bind-mount log
│   └── docker/
│       ├── modsecurity/
│       │   ├── Dockerfile             # Build Nginx tích hợp ModSecurity v3 & OWASP CRS v4
│       │   ├── conf/
│       │   │   ├── nginx.conf         # Cấu hình Reverse Proxy trỏ về DVWA nội bộ
│       │   │   └── modsec.conf        # Bật ModSecurity và cấu hình xuất log Single-line JSON
│       │   └── owasp-crs/             # Thư mục chứa bộ luật OWASP Core Rule Set v4
│       └── dvwa/
│           └── init.sql               # Script khởi tạo cơ sở dữ liệu mẫu cho DVWA
├── vm3-wazuh-manager/                 # Phân vùng VM 3: Cấu hình tùy chỉnh cho Wazuh AIO
│   ├── agent-config/
│   │   └── ossec.conf                 # Cấu hình ossec.conf của Wazuh Agent (đọc log JSON qua localfile)
│   └── custom-rules/
│       └── modsec_crs4_rules.xml      # File luật tùy chỉnh bắt sự kiện JSON, mã 403 và Active Response
└── scripts/                           # Các công cụ tự động hóa và kịch bản kiểm thử
    ├── setup-vm2-agent.sh             # Script cài đặt Wazuh Agent trên VM 2 và kết nối về VM 3
    └── test-attacks.sh                # Script giả lập tấn công (SQLi, XSS, Path Traversal) để test SIEM
```

---

## 🌐 Quy Hoạch Địa Chỉ Mạng (Network Scheme)

| Thực thể | Hệ Điều Hành | Địa Chỉ IP | Dịch Vụ Chính |
| :--- | :--- | :--- | :--- |
| **VM 1: Attacker** | Kali Linux | `192.168.1.10` | Công cụ tấn công HTTP (`curl`, `test-attacks.sh`) |
| **VM 2: Web Target**| Ubuntu / Debian | `192.168.1.20` | ModSecurity CRS v4 (Port 80) + DVWA + Wazuh Agent |
| **VM 3: Wazuh AIO** | Ubuntu Server | `192.168.1.30` | Wazuh Manager (Port 1514), Indexer (Port 9200), Dashboard (Port 443) |

---

## 🚀 Hướng Dẫn Vận Hành Lab Từng Bước

### Bước 1: Chuẩn bị VM 3 (Wazuh Manager)
1. Cài đặt Wazuh All-in-One trên máy chủ `192.168.1.30`.
2. Sao chép bộ luật tùy chỉnh ModSecurity CRS v4 vào Wazuh Manager:
   ```bash
   sudo cp vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml /var/ossec/etc/rules/
   sudo chown wazuh:wazuh /var/ossec/etc/rules/modsec_crs4_rules.xml
   sudo chmod 660 /var/ossec/etc/rules/modsec_crs4_rules.xml
   ```
3. Khởi động lại dịch vụ Wazuh Manager để nạp luật mới:
   ```bash
   sudo systemctl restart wazuh-manager
   ```

### Bước 2: Triển khai VM 2 (Web Target & WAF)
1. Di chuyển vào thư mục `vm2-web-target` và khởi chạy các container:
   ```bash
   cd vm2-web-target
   docker compose up -d --build
   ```
2. Cài đặt và cấu hình Wazuh Agent tự động trên host VM 2:
   ```bash
   sudo bash ../scripts/setup-vm2-agent.sh 192.168.1.30 vm2-web-target
   ```
   *Script sẽ tự động tạo thư mục `/var/log/modsec/`, cài đặt Wazuh Agent và cấu hình `<localfile>` đọc file log JSON.*

### Bước 3: Thực hiện kiểm thử từ VM 1 (Attacker)
1. Trên máy Kali Linux (`192.168.1.10`), chạy script giả lập tấn công:
   ```bash
   bash scripts/test-attacks.sh http://192.168.1.20
   ```
2. Quan sát kết quả:
   - Các truy cập thông thường trả về `HTTP 200`.
   - Các request chứa payload tấn công (SQLi, XSS, Path Traversal, RCE) bị ModSecurity chặn lại với mã `HTTP 403 Forbidden`.

### Bước 4: Quan sát kết quả trên Wazuh Dashboard
1. Đăng nhập vào Wazuh Dashboard: `https://192.168.1.30` (tài khoản mặc định: `admin`).
2. Vào mục **Security events** và lọc theo rule ID hoặc group:
   - `rule.groups: "modsecurity"` hoặc `rule.id: (100101 OR 100102 OR 100103 OR 100104 OR 100105)`
3. Kiểm tra tính năng Active Response chặn IP tấn công khi Rule `100110` được kích hoạt.

