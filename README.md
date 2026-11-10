# Wazuh ModSecurity SIEM Lab

Dự án triển khai mô hình phòng lab SOC / SIEM chuẩn công nghiệp giám sát ứng dụng Web, tích hợp giữa **Wazuh SIEM**, **WAF ModSecurity v3 (OWASP Core Rule Set v4)** và môi trường ứng dụng thử nghiệm **DVWA**.

---

## 📁 Cấu Trúc Thư Mục Dự Án (Repository Structure)

```plaintext
.
├── .env.example                       # File mẫu quản lý biến môi trường động
├── README.md                          # Hướng dẫn tổng quan, quy hoạch mạng và cách vận hành lab
├── docs/
│   ├── architecture.md                # Tài liệu kiến trúc hệ thống chuẩn hóa
│   ├── deployment-plan.md              # Kế hoạch triển khai chi tiết & Master Checklist
│   ├── phase0-vmware-setup.md         # Cẩm nang chi tiết thiết lập hạ tầng ảo hóa VMware
│   ├── phase1-workspace-env-setup.md  # Cẩm nang chi tiết quản trị cấu hình (.env, Git, SSH)
│   ├── phase2-waf-docker-setup.md     # Cẩm nang chi tiết triển khai WAF ModSecurity CRS v4 & DVWA
│   ├── phase3-wazuh-siem-setup.md     # Cẩm nang chi tiết cấu hình Wazuh SIEM, Rules & Active Response
│   ├── phase4-attack-simulation.md    # Cẩm nang chi tiết giả lập tấn công, xác thực phòng vệ & unblock
│   └── phase5-windows-endpoint-setup.md # Cẩm nang giám sát Endpoint Windows 10 (Agent, Sysmon, Rules, AR)
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
│   ├── custom-rules/
│   │   ├── modsec_crs4_rules.xml      # File luật tùy chỉnh bắt sự kiện JSON, mã 403 và Active Response
│   │   └── windows_rules.xml          # Luật Windows/Sysmon/PowerShell (100200-100213) cho VM 4
│   └── shared/windows/
│       └── agent.conf                 # Cấu hình tập trung cho agent group "windows" (kênh Sysmon, PowerShell, Defender)
├── vm4-windows-client/                # Phân vùng VM 4: Windows 10 Client (Endpoint)
│   └── active-response/
│       ├── win-firewall-drop.cmd      # Wrapper Active Response được Wazuh Agent gọi
│       └── win-firewall-drop.ps1      # Chặn/gỡ chặn IP bằng Windows Defender Firewall
└── scripts/                           # Các công cụ tự động hóa và kịch bản kiểm thử
    ├── setup-vm2-agent.sh             # Script cài đặt Wazuh Agent trên VM 2 và kết nối về VM 3
    ├── setup-vm2-active-response.sh   # Script cấu hình Active Response chuỗi DOCKER-USER trên VM 2
    ├── test-attacks.sh                # Script giả lập tấn công tự động (SQLi, XSS, LFI, RCE, Active Response)
    ├── setup-vm4-windows-agent.ps1    # Cài Wazuh Agent + Sysmon + Audit Policy + AR trên VM 4 (Windows 10)
    ├── simulate-windows-events.ps1    # Sinh sự kiện hậu khai thác an toàn trên VM 4 để kiểm thử luật
    ├── test-windows-attacks.sh        # SMB brute-force từ Kali vào VM 4, kiểm chứng Active Response
    └── export-demo-alerts.sh          # Xuất cảnh báo demo (JSONL có nhãn ground_truth + summary) cho AI agent
```

---

## 🌐 Quy Hoạch Địa Chỉ Mạng (Network Scheme)

| Thực thể | Hệ Điều Hành | Địa Chỉ IP | Dịch Vụ Chính |
| :--- | :--- | :--- | :--- |
| **VM 1: Attacker** | Kali Linux | `192.168.1.10` | Công cụ tấn công HTTP (`curl`, `test-attacks.sh`) |
| **VM 2: Web Target**| Ubuntu / Debian | `192.168.1.20` | ModSecurity CRS v4 (Port 80) + DVWA + Wazuh Agent |
| **VM 3: Wazuh AIO** | Ubuntu Server | `192.168.1.30` | Wazuh Manager (Port 1514), Indexer (Port 9200), Dashboard (Port 443) |
| **VM 4: Windows Client** | Windows 10 Pro | `192.168.1.40` | Wazuh Agent (group `windows`) + Sysmon + Windows Defender Firewall |

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


### Bước 5: Mở rộng giám sát Endpoint Windows 10 (VM 4)
1. Trên VM 3: tạo agent group `windows`, nạp `agent.conf`, `windows_rules.xml` và khai báo Active Response `win-firewall-drop` (Rule `100201`).
2. Trên VM 4 (PowerShell Admin), cài Wazuh Agent + Sysmon + Audit Policy:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\setup-vm4-windows-agent.ps1 -ManagerIP 192.168.1.30 -AgentName vm4-win-client
   ```
3. Kiểm thử: chạy `scripts\simulate-windows-events.ps1` trên VM 4 và `bash scripts/test-windows-attacks.sh 192.168.1.40` trên Kali.
4. Trên Dashboard lọc `rule.groups: "custom_windows"`.

👉 Chi tiết từng bước: [`docs/phase5-windows-endpoint-setup.md`](docs/phase5-windows-endpoint-setup.md).
