# Hướng Dẫn Chi Tiết Giai Đoạn 1: Khởi Tạo Workspace & Quản Trị Cấu Hình (.env & Git)

Tài liệu này là cẩm nang kỹ thuật hướng dẫn chi tiết từng bước (Step-by-step) dành cho kỹ sư triển khai thiết lập môi trường làm việc chuẩn hóa DevOps, quản lý mã nguồn Git, cấu hình biến môi trường động `.env`, và thiết lập kết nối điều khiển trung tâm (SSH Key-based) cho toàn bộ phòng lab **Wazuh ModSecurity SIEM**.

---

## 🎯 1. MỤC TIÊU CỦA GIAI ĐOẠN 1

Sau khi hoàn thành Giai đoạn 0 (3 máy ảo đã thông mạng `192.168.1.0/24`), Giai đoạn 1 sẽ đảm bảo:
1. **Tách biệt cấu hình và mã nguồn (12-Factor App):** Toàn bộ tham số mạng, IP máy chủ, và token cảnh báo được điều khiển qua file `.env`, không hardcode vào script.
2. **Bảo mật mã nguồn:** Loại trừ tuyệt đối các file nhạy cảm (`.env`, private keys, certificates, log files) khỏi Git tracking qua `.gitignore`.
3. **Đồng bộ hóa Git Remote:** Đẩy toàn bộ codebase lên GitHub/GitLab và clone về các máy ảo VM 1, VM 2, VM 3.
4. **Tối ưu hóa vận hành (SSH Alias & Passwordless):** Thiết lập khóa SSH Ed25519 từ máy tính Host (Windows) để điều khiển 3 máy ảo nhanh chóng mà không cần nhập mật khẩu mỗi lần.
5. **Chuẩn hóa script Linux:** Xử lý lỗi ngắt dòng Windows CRLF sang Unix LF (`\r`) để script bash chạy mượt mà trên môi trường Linux.

---

## ⚙️ 2. BƯỚC 1: CẤU HÌNH BIẾN MÔI TRƯỜNG ĐỘNG (.ENV)

### 2.1. Khởi tạo file `.env` từ file mẫu
Trên máy Host (hoặc máy ảo quản trị), tạo file `.env` từ file template [`.env.example`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/.env.example):

* **Trên Windows PowerShell:**
  ```powershell
  Copy-Item .env.example .env
  ```
* **Trên Linux / Bash:**
  ```bash
  cp .env.example .env
  ```

---

### 2.2. Giải thích chi tiết các tham số trong `.env`
Mở file `.env` bằng trình soạn thảo (VS Code, Nano, hoặc Notepad):

```ini
# =============================================================================
# Wazuh ModSecurity SIEM Lab - Environment Variables
# =============================================================================

# --- 1. Môi trường triển khai ---
# "local" (VMware / Hyper-V dải 192.168.1.x) hoặc "cloud" (VPS / AWS Public IP)
DEPLOY_ENV=local

# --- 2. Quy hoạch IP & Port các Node ---
# VM 1: Attacker (Kali Linux)
ATTACKER_IP=192.168.1.10

# VM 2: Web Server & WAF Host (Docker Host)
TARGET_IP=192.168.1.20
TARGET_PORT=80
TARGET_SCHEME=http

# VM 3: Wazuh All-In-One Server (Manager + Indexer + Dashboard)
WAZUH_MANAGER_IP=192.168.1.30
WAZUH_AGENT_NAME=vm2-web-target
WAZUH_AGENT_GROUP=web-servers

# --- 3. Tối ưu hiệu năng SIEM Core (Wazuh Indexer) ---
# Bộ nhớ Java Heap phân bổ cho OpenSearch (Chuẩn lab: 4g)
INDEXER_JAVA_HEAP=4g

# --- 4. Tích hợp cảnh báo Telegram Webhook (Tùy chọn) ---
TELEGRAM_ALERT_ENABLED=false
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here
TELEGRAM_CHAT_ID=your_telegram_chat_id_here

# --- 5. Đường dẫn lưu trữ & Mức độ bảo mật DVWA ---
MODSEC_LOG_DIR=/var/log/modsec
DVWA_SECURITY_LEVEL=low
```

---

### 2.3. Helper Function nạp biến `.env` an toàn vào Bash Scripts
Để các script trong thư mục `scripts/` (như `setup-vm2-agent.sh` và `test-attacks.sh`) tự động nạp file `.env` mà không bị lỗi khi có dòng comment `#` hoặc dòng trống, chuẩn cú pháp sau được tích hợp sẵn:

```bash
# Đoạn code nạp .env chuẩn POSIX:
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
elif [ -f ../.env ]; then
  export $(grep -v '^#' ../.env | xargs)
fi
```

---

## 🔒 3. BƯỚC 2: QUẢN TRỊ MÃ NGUỒN VỚI GIT & ĐẨY LÊN GITHUB

### 3.1. Xác thực file `.gitignore`
Đảm bảo file [`.gitignore`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/.gitignore) đã chặn toàn bộ file nhạy cảm:

```gitignore
# Không commit file cấu hình chứa mật khẩu / token
.env
.env.local
*.pem
*.key

# Không commit log phát sinh trong quá trình chạy lab
*.log
/var/log/
*.pid

# File rác hệ điều hành & IDE
.DS_Store
Thumbs.db
desktop.ini
.vscode/
.idea/
```

Kiểm tra trạng thái bằng lệnh:
```bash
git status
```
*(Đảm bảo file `.env` KHÔNG nằm trong danh sách "Untracked files" hoặc "Changes to be committed").*

---

### 3.2. Đẩy toàn bộ mã nguồn lên GitHub Remote Repository
Nếu bạn chưa đẩy code lên GitHub, thực hiện 4 bước sau:

1. **Tạo repository mới trên GitHub:**
   * Truy cập: [https://github.com/new](https://github.com/new)
   * Tên Repository: `wazuh-modsec-siem-lab`
   * Chế độ: **Public** hoặc **Private**.
   * *Lưu ý: Không tích chọn "Add a README file" hay ".gitignore" vì repo local đã có sẵn.*
   * Nhấn **Create repository**.

2. **Liên kết Remote và Push code từ máy Host:**
   Mở terminal tại thư mục dự án và chạy:
   ```bash
   # 1. Thêm toàn bộ file vào staging
   git add .

   # 2. Tạo commit cho Phase 1
   git commit -m "feat(phase1): setup workspace environment and git management"

   # 3. Liên kết với GitHub URL của bạn (thay URL bên dưới)
   git remote add origin https://github.com/<USERNAME_CUA_BAN>/wazuh-modsec-siem-lab.git

   # 4. Đẩy mã nguồn lên nhánh chính (main)
   git branch -M main
   git push -u origin main
   ```

---

## 🚀 4. BƯỚC 3: ĐỒNG BỘ MÃ NGUỒN VỀ CÁC MÁY ẢO

Sau khi mã nguồn đã có trên GitHub, tiến hành đồng bộ về các node máy ảo để chuẩn bị cho Giai đoạn 2 và 3.

### 4.1. Đồng bộ về VM 2: Web Target & WAF (`192.168.1.20`)
Đăng nhập vào VM 2:
```bash
# 1. Cài đặt git nếu chưa có
sudo apt update && sudo apt install -y git

# 2. Clone repository về thư mục home
cd ~
git clone https://github.com/<USERNAME_CUA_BAN>/wazuh-modsec-siem-lab.git
cd wazuh-modsec-siem-lab

# 3. Khởi tạo file .env trên VM 2
cp .env.example .env
```

---

### 4.2. Đồng bộ về VM 1: Attacker (Kali Linux - `192.168.1.10`)
Đăng nhập vào VM 1:
```bash
cd ~
git clone https://github.com/<USERNAME_CUA_BAN>/wazuh-modsec-siem-lab.git
cd wazuh-modsec-siem-lab
cp .env.example .env
```

---

### 4.3. Đồng bộ về VM 3: Wazuh AIO SIEM (`192.168.1.30`)
Đăng nhập vào VM 3:
```bash
cd ~
git clone https://github.com/<USERNAME_CUA_BAN>/wazuh-modsec-siem-lab.git
```
*(Mục đích để sẵn sàng bộ file custom rules `vm3-wazuh-manager/custom-rules/modsec_crs4_rules.xml` nạp vào Wazuh Manager ở Giai đoạn 3).*

---

## 🔑 5. BƯỚC 4: THIẾT LẬP SSH KHÔNG MẬT KHẨU (PASSWORDLESS) TỪ HOST VÀO 3 VM

Để quá trình làm việc DevOps thuận tiện, bạn nên điều khiển cả 3 máy ảo từ một cửa sổ terminal máy Host (Windows) duy nhất qua SSH Key mà không cần gõ mật khẩu.

### 5.1. Tạo SSH Key trên máy Host (Windows PowerShell / Terminal)
1. Mở PowerShell trên Windows và tạo cặp khóa Ed25519 chuẩn bảo mật cao:
   ```powershell
   ssh-keygen -t ed25519 -C "admin-soc-lab"
   # Nhấn Enter 3 lần để để trống passphrase
   ```

2. Đẩy Public Key lên cả 3 máy ảo:
   ```powershell
   # Đẩy lên VM 1 (Kali Linux)
   type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh kali@192.168.1.10 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

   # Đẩy lên VM 2 (Web Target)
   type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@192.168.1.20 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

   # Đẩy lên VM 3 (Wazuh SIEM)
   type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh ubuntu@192.168.1.30 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
   ```

---

### 5.2. Cấu hình SSH Config Alias tiện dụng
Trên máy Windows, tạo hoặc mở file `C:\Users\<TÊN_USER>\.ssh\config` và thêm vào nội dung:

```ssh
Host vm1-attacker
    HostName 192.168.1.10
    User kali
    IdentityFile ~/.ssh/id_ed25519

Host vm2-target
    HostName 192.168.1.20
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519

Host vm3-wazuh
    HostName 192.168.1.30
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519
```

**Thành quả:** Kể từ bây giờ, từ bất kỳ cửa sổ CMD/PowerShell nào trên Windows, bạn chỉ cần gõ:
```powershell
ssh vm2-target
```
Hệ thống sẽ đăng nhập thẳng vào VM 2 mà không hỏi mật khẩu!

---

## 🛠️ 6. BƯỚC 5: PHÂN QUYỀN & CHUYỂN ĐỔI LINE ENDINGS (CRLF $\rightarrow$ LF)

Khi thao tác code trên Windows, các file script bash thường bị tự động gán ký tự ngắt dòng kiểu DOS/Windows (`\r\n` - CRLF). Khi mang sang Linux chạy sẽ gặp lỗi kinh điển:
`bash: ./script.sh: /bin/bash^M: bad interpreter: No such file or directory`

### Xử lý triệt để trên VM 1 và VM 2:
Sau khi clone repo về máy ảo Linux, chạy các lệnh sau trong thư mục `wazuh-modsec-siem-lab`:

```bash
# 1. Cài đặt tiện ích dos2unix (nếu cần)
sudo apt update && sudo apt install -y dos2unix

# 2. Chuẩn hóa line endings sang chuẩn Unix (LF)
dos2unix scripts/*.sh

# (Hoặc dùng sed nếu không muốn cài dos2unix):
# sed -i 's/\r$//' scripts/*.sh

# 3. Cấp quyền thực thi cho toàn bộ script
chmod +x scripts/*.sh

# 4. Kiểm tra quyền
ls -la scripts/
```
*(Kết quả các script phải có cờ `-rwxr-xr-x`)*.

---

## ✅ 7. BƯỚC 6: CHỐT CHẶN NGHIỆM THU GIAI ĐOẠN 1 (CHECKPOINT 1)

Thực hiện kiểm tra 5 tiêu chí sau để chính thức đóng Giai đoạn 1:

| TT | Hạng mục kiểm tra | Lệnh xác thực | Kết quả kỳ vọng (PASS) |
| :---: | :--- | :--- | :--- |
| **1** | **Kiểm tra Git Clean & .gitignore** | `git status` trên máy Host | Không xuất hiện file `.env` hoặc file nhạy cảm trong Git. |
| **2** | **Kiểm tra GitHub Sync** | Truy cập link repo trên trình duyệt | Code và đầy đủ các file tài liệu trong `docs/` đã hiển thị trên GitHub. |
| **3** | **Kiểm tra SSH Alias** | `ssh vm2-target "hostname -I"` từ Host | Đăng nhập tức thời, in ra IP `192.168.1.20` mà không hỏi password. |
| **4** | **Kiểm tra Codebase trên VM 2 & 1** | `ls -la ~/wazuh-modsec-siem-lab` | Có đầy đủ thư mục `vm2-web-target`, `vm3-wazuh-manager`, `scripts` và file `.env`. |
| **5** | **Kiểm tra Script Execution** | `bash scripts/test-attacks.sh --help` hoặc dry-run | Script chạy mượt mà, không gặp lỗi `^M` hoặc `Permission denied`. |

---

## 🎯 KẾT LUẬN GIAI ĐOẠN 1
Khi toàn bộ 5 tiêu chí trên đều **PASS**, không gian làm việc (Workspace), mã nguồn, và kênh điều khiển SSH đã hoàn toàn sẵn sàng.

👉 Tiếp theo, bạn có thể bắt tay ngay vào **Giai đoạn 2: Triển khai Lớp WAF & Docker trên VM 2 (Web Target)** theo hướng dẫn trong [**`docs/deployment-plan.md`**](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/docs/deployment-plan.md).

