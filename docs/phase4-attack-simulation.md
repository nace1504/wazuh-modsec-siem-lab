# Hướng Dẫn Chi Tiết Giai Đoạn 4: Tự Động Hóa Giả Lập Tấn Công & Kiểm Chứng Phòng Vệ (Attack Simulation & Verification)

Tài liệu này là cẩm nang kỹ thuật thực chiến chi tiết từng bước (Step-by-step) dành cho sinh viên/kỹ sư thực hiện **Giai đoạn 4** của Đồ án tốt nghiệp: **Giả lập tấn công từ máy Attacker VM 1 (Kali Linux `192.168.1.10`)**, kiểm chứng năng lực phát hiện và bóc tách của **WAF ModSecurity CRS v4 (VM 2 `192.168.1.20`)**, giám sát phân tích tương quan sự kiện trên **Wazuh SIEM (VM 3 `192.168.1.30`)**, và thẩm định cơ chế phản ứng tự động **Active Response** khóa IP trong chuỗi `DOCKER-USER`.

---

## 🗺️ 1. MÔ HÌNH DIỄN TẬP TẤN CÔNG & PHÒNG THỦ (CYBER RANGE LAB)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ VM 1: ATTACKER HOST (Kali Linux - 192.168.1.10)                        │
│                                                                         │
│   [Automated Suite: test-attacks.sh]                                    │
│   ├── Phase 1: Baseline Traffic (HTTP 200/302)                         │
│   ├── Phase 2: Web Attacks (SQLi, XSS, Path Traversal, RCE)            │
│   ├── Phase 3: Burst Attack (5 requests -> Total 11 >= 8)               │
│   └── Phase 4: Automated Verification (Connection Timed Out)            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     │ Gửi HTTP Requests (Port 80)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ VM 2: WEB TARGET & WAF HOST (Ubuntu Server - 192.168.1.20)              │
│                                                                         │
│   1. iptables Tường lửa: Kiểm tra gói tin ở chuỗi DOCKER-USER          │
│      ├── Chưa khóa: Cho phép gói tin đi tiếp vào Nginx WAF             │
│      └── Đã khóa: DROP gói tin của 192.168.1.10 ngay lập tức!           │
│                                                                         │
│   2. Nginx ModSecurity CRS v4 (Docker Reverse Proxy :80):               │
│      ├── Phân tích cú pháp payload HTTP theo CRS v4                     │
│      ├── Chặn đứng đòn tấn công với HTTP 403 Forbidden                 │
│      └── Ghi log kiểm toán Single-line JSON -> /var/log/modsec/audit.log│
│                                                                         │
│   3. Wazuh Agent 4.8.2 (Host Daemon):                                   │
│      ├── Thu thập file log JSON qua <localfile>                         │
│      └── Gửi mã hóa sự kiện về SIEM qua cổng TCP 1514                   │
│                                                                         │
│   4. Active Response Handler:                                           │
│      └── Thực thi /var/ossec/active-response/bin/docker-firewall-drop   │
└────────────────────────────────────▲────────────────────────────────────┘
                                     │
                                     │ Nhận lệnh Active Response (add/delete)
                                     │ & Gửi Event Log qua TCP 1514
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ VM 3: WAZUH SIEM & ANALYTICS CENTER (Ubuntu Server - 192.168.1.30)       │
│                                                                         │
│   1. Wazuh Manager 4.8.2:                                               │
│      ├── Built-in JSON Decoder: Giải mã dynamic fields                  │
│      ├── Ruleset (modsec_crs4_rules.xml):                               │
│      │   ├── Rule 100101 (HTTP 403 Forbidden)                          │
│      │   ├── Rule 100102 (SQL Injection - MITRE T1190)                  │
│      │   ├── Rule 100103 (Cross-Site Scripting - MITRE T1059.007)       │
│      │   ├── Rule 100104 (Path Traversal / LFI - MITRE T1083)           │
│      │   ├── Rule 100105 (Command Injection / RCE - MITRE T1059)        │
│      │   └── Rule 100110 (Correlation: >= 8 attacks/60s -> LEVEL 14)    │
│      └── Active Response Engine: Ra lệnh VM 2 khóa IP 192.168.1.10      │
│                                                                         │
│   2. Wazuh Indexer & Dashboard (HTTPS :443):                            │
│      └── Lưu trữ OpenSearch, trực quan hóa biểu đồ SOC Analyst          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 2. MỤC TIÊU CỦA GIAI ĐOẠN 4

1. **Kiểm thử đa dạng các vector tấn công Web OWASP Top 10:** Chứng minh năng lực nhận diện của bộ quy tắc Core Rule Set (CRS) v4 trước các payload SQLi, XSS, Path Traversal, và RCE.
2. **Kiểm chứng cơ chế giám sát SOC thời gian thực:** Xác thực rằng Wazuh Manager bóc tách đúng trường `transaction.client_ip`, ánh xạ chính xác kỹ thuật MITRE ATT&CK và gán nhãn mức độ nghiêm trọng (Level 7 - 14).
3. **Thẩm định cơ chế phản ứng tự động (Active Response):** Chứng minh khi tần suất vi phạm vượt ngưỡng quy định ($\ge 8$ lần trong 60 giây), hệ thống tự động khóa địa chỉ IP kẻ tấn công trong chuỗi `DOCKER-USER` của iptables mà không cần can thiệp thủ công.
4. **Thu thập dữ liệu, log và biểu đồ phục vụ báo cáo ĐATN:** Cung cấp đầy đủ cú pháp trích xuất dữ liệu, ảnh chụp giao diện Wazuh Dashboard và bảng tổng hợp số liệu để đưa vào tài liệu thuyết minh đồ án.

---

## 🛠️ 3. DANH MỤC CÁC KỊCH BẢN TẤN CÔNG THỰC CHIẾN

Bảng đối chiếu kỹ thuật giữa các đòn tấn công, luật WAF CRS v4 và luật Wazuh SIEM:

| Kịch bản | Vector tấn công | Payload minh họa | Mã CRS v4 WAF | Wazuh Rule ID | MITRE ATT&CK | Tiêu chuẩn |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: |
| **Kịch bản 1** | Baseline Traffic | `GET /` hoặc `GET /login.php` | N/A (Allow) | N/A | N/A | N/A |
| **Kịch bản 2.1** | SQLi (In-band) | `/?id=1' OR '1'='1` | `942100` | **`100102`** (L10) | **T1190** | PCI-DSS 6.5.1 |
| **Kịch bản 2.2** | SQLi (Union-based)| `/?id=1 UNION SELECT null,version()--`| `942140` | **`100102`** (L10) | **T1190** | PCI-DSS 6.5.1 |
| **Kịch bản 3.1** | XSS (Script tag) | `/?search=<script>alert('XSS')</script>`| `941100` | **`100103`** (L10) | **T1059.007**| PCI-DSS 6.5.7 |
| **Kịch bản 3.2** | XSS (Event tag)  | `/?search=<img src=x onerror=alert(1)>`| `941160` | **`100103`** (L10) | **T1059.007**| PCI-DSS 6.5.7 |
| **Kịch bản 4** | Path Traversal / LFI| `/?page=../../../../etc/passwd` | `930100` | **`100104`** (L10) | **T1083** | PCI-DSS 6.5.8 |
| **Kịch bản 5** | Command Injection / RCE| `/?cmd=127.0.0.1;cat /etc/passwd` | `932100` | **`100105`** (L12) | **T1059** | PCI-DSS 6.5.2 |
| **Kịch bản 6** | Tấn công lặp lại dồn dập | 5 burst attacks liên tiếp trong 2s | `949110` | **`100110`** (L14) | **T1190** | **Khóa IP Active Response** |

---

## 🚀 4. QUY TRÌNH THỰC THI KIỂM THỬ

### 4.1. Chuẩn bị môi trường trên VM 1 (Kali Linux `192.168.1.10`)
Đăng nhập vào terminal của **VM 1**:

```bash
# 1. Điều hướng vào thư mục dự án
cd ~/wazuh-modsec-siem-lab

# 2. Đồng bộ mã nguồn mới nhất từ GitHub
git checkout -- .
git pull

# 3. Cấp quyền thực thi cho kịch bản tấn công
chmod +x scripts/test-attacks.sh
```

---

### 4.2. Chạy kịch bản tự động hóa toàn diện ([`scripts/test-attacks.sh`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/scripts/test-attacks.sh))
Chạy script kiểm thử hướng tới mục tiêu VM 2:

```bash
bash scripts/test-attacks.sh http://192.168.1.20
```

#### Kết quả kỳ vọng trên màn hình terminal Kali Linux:
```text
==========================================================
 WAF & SIEM Security Pipeline Verification Suite         
 Target Host: http://192.168.1.20                             
==========================================================

--- [Phase 1: Normal Traffic Baseline] ---
[*] Testing: Normal Index Page ... [PASS] HTTP 200 (As expected)

--- [Phase 2: Demonstration of OWASP CRS v4 Protection] ---
[*] Testing: SQL Injection (OR 1=1) ... [PASS] HTTP 403 (As expected)
[*] Testing: SQL Injection (UNION SELECT) ... [PASS] HTTP 403 (As expected)
[*] Testing: Cross-Site Scripting (Script Tag) ... [PASS] HTTP 403 (As expected)
[*] Testing: Cross-Site Scripting (Img Onerror) ... [PASS] HTTP 403 (As expected)
[*] Testing: Path Traversal (/etc/passwd) ... [PASS] HTTP 403 (As expected)
[*] Testing: Command Injection (; cat /etc/passwd) ... [PASS] HTTP 403 (As expected)

--- [Phase 3: High-Frequency Trigger for Active Response] ---
[*] Sending 5 consecutive burst attacks to trigger Rule 100110 (Threshold >= 8).....
[✓] Total attacks in 60s: 11 (Exceeded Rule 100110 threshold >= 8)

--- [Phase 4: Automated Verification of IP Blocking] ---
[*] Verifying firewall drop status from Attacker host ... [PASS] Attacker IP is successfully BLOCKED! (Connection timed out)
[✓] Full SOC/SIEM Pipeline Test PASSED (100% SUCCESS)

----------------------------------------------------------
👉 To unblock IP immediately on VM 2, run:
   sudo /var/ossec/active-response/bin/docker-firewall-drop delete - 192.168.1.10
----------------------------------------------------------
```

---

### 4.3. Kiểm thử thủ công từng đòn đánh (Chụp ảnh minh chứng ĐATN)
Để có ảnh chụp màn hình đẹp cho báo cáo và slide thuyết trình, bạn có thể gửi từng payload thủ công qua `curl` hoặc nhập trực tiếp trên trình duyệt Kali Linux:

#### 1. SQL Injection:
```bash
curl -i "http://192.168.1.20/?id=1'%20OR%20'1'='1"
```
* **Kỳ vọng:** Trả về `HTTP/1.1 403 Forbidden`, Server header: `nginx`.

#### 2. Cross-Site Scripting (XSS):
```bash
curl -i "http://192.168.1.20/?search=%3Cscript%3Ealert('PTIT_SOC')%3C/script%3E"
```
* **Kỳ vọng:** `HTTP/1.1 403 Forbidden`.

#### 3. Path Traversal / LFI:
```bash
curl -i "http://192.168.1.20/?page=../../../../etc/passwd"
```
* **Kỳ vọng:** `HTTP/1.1 403 Forbidden`.

#### 4. Remote Code Execution (RCE):
```bash
curl -i "http://192.168.1.20/?cmd=127.0.0.1;cat%20/etc/passwd"
```
* **Kỳ vọng:** `HTTP/1.1 403 Forbidden`.

---

## 🔍 5. KIỂM CHỨNG TRÊN TỪNG THÀNH PHẦN HỆ THỐNG

### 5.1. Kiểm chứng trên VM 2 (Web Target & WAF Host - `192.168.1.20`):

#### 1. Kiểm tra log kiểm toán WAF:
```bash
# Xem sự kiện JSON mới nhất được ModSecurity ghi nhận
sudo tail -n 1 /var/log/modsec/modsec_audit.log | jq .
```
> Trích xuất các trường quan trọng:
> * `client_ip`: `192.168.1.10`
> * `http_code`: `403`
> * `ruleId`: `942100` / `941100` / `930100` / `932100`
> * `messages`: Chi tiết luật vi phạm của OWASP CRS v4.

#### 2. Kiểm tra chuỗi tường lửa `DOCKER-USER`:
```bash
sudo iptables -L DOCKER-USER -n -v
```
> **Kết quả kỳ vọng:**
> ```text
> Chain DOCKER-USER (1 references)
>  pkts bytes target     prot opt in     out     source               destination         
>     5   300 DROP       all  --  *      *       192.168.1.10         0.0.0.0/0
> ```
> *(Rule `DROP` đang hoạt động và số lượng packet bị drop tăng lên khi Kali gửi request)*!

#### 3. Kiểm tra file nhật ký Active Response:
```bash
sudo cat /var/ossec/logs/active-responses.log
```
> **Kết quả kỳ vọng:**
> ```text
> 2026/11/01 23:58:12 docker-firewall-drop: Successfully BLOCKED attack IP: 192.168.1.10 in DOCKER-USER chain
> ```

---

### 5.2. Kiểm chứng trên VM 3 (Wazuh SIEM Server - `192.168.1.30`):

#### 1. Xem file cảnh báo thời gian thực (`alerts.json`):
```bash
sudo tail -n 20 /var/ossec/logs/alerts/alerts.json | jq '{timestamp: .timestamp, rule_id: .rule.id, level: .rule.level, description: .rule.description, src_ip: .data.transaction.client_ip}'
```
> **Kỳ vọng đầu ra:** Hiển thị danh sách các Alert đã được kích hoạt:
> * Rule `100102` (SQLi - Level 10)
> * Rule `100103` (XSS - Level 10)
> * Rule `100104` (Path Traversal - Level 10)
> * Rule `100105` (RCE - Level 12)
> * Rule `100110` (Active Response Trigger - Level 14)

---

## 📊 6. HƯỚNG DẪN ĐIỀU TRA TRÊN WAZUH DASHBOARD (SOC ANALYST UI)

Mở trình duyệt trên máy Host (Windows) truy cập: **`https://192.168.1.30`**  
*(Đăng nhập tài khoản `admin` / mật khẩu lưu từ Phase 3)*.

```
┌─────────────────────────────────────────────────────────────────────────┐
│ WAZUH DASHBOARD - SOC ANALYST INVESTIGATION VIEW                        │
├─────────────────────────────────────────────────────────────────────────┤
│ Filter: rule.groups: "modsecurity"                                      │
├─────────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────┐ │
│ │ Total Alerts         │  │ High Severity (>=10) │  │ Active Response │ │
│ │        12            │  │          11          │  │    1 (BLOCKED)  │ │
│ └──────────────────────┘  └──────────────────────┘  └─────────────────┘ │
│                                                                         │
│ [Attack Distribution by Rule ID]                                        │
│  Rule 100102 (SQLi):    ████████████ (6)                                │
│  Rule 100103 (XSS):     ████ (2)                                        │
│  Rule 100104 (LFI):     ██ (1)                                          │
│  Rule 100105 (RCE):     ██ (2)                                          │
│  Rule 100110 (AR Drop): ██ (1 - Level 14)                              │
│                                                                         │
│ [Top Attacker Source IP]                                                │
│  192.168.1.10 (Kali Linux) ──────────────────> 100% Events              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Các bước thao tác điều tra chi tiết:
1. **Truy cập module Security Events:**
   * Nhấp biểu tượng Menu góc trên bên trái $\rightarrow$ **Security events**.
2. **Thiết lập bộ lọc (Search Filter):**
   * Nhập vào thanh tìm kiếm: `rule.groups: "modsecurity"` $\rightarrow$ Nhấn **Update**.
   * Thêm bộ lọc phụ: `data.transaction.client_ip: "192.168.1.10"`.
3. **Phân tích chi tiết một bản ghi sự kiện (Event Drill-down):**
   * Bấm vào nút mở rộng (`>`) của sự kiện có Rule ID `100110` hoặc `100105`:
   * **`rule.id`**: `100110`
   * **`rule.level`**: `14` (Critical Security Incident)
   * **`rule.mitre.id`**: `T1190` (Exploit Public-Facing Application)
   * **`rule.mitre.technique`**: `Exploit Public-Facing Application`
   * **`data.transaction.client_ip`**: `192.168.1.10`
   * **`data.transaction.request.uri`**: `/?id=test_burst_3%27%20OR%201=1--`
   * **`data.transaction.response.http_code`**: `403`
4. **Chụp ảnh báo cáo:**
   * Chụp biểu đồ hình cột phân bố các loại tấn công.
   * Chụp bảng chi tiết sự kiện hiển thị MITRE ATT&CK ID và thông tin kẻ tấn công.

---

## 🔓 7. QUY TRÌNH GỠ KHÓA IP (UNBLOCK WORKFLOW)

Sau khi kiểm thử xong hoặc khi cần thực hiện lại kịch bản, bạn tiến hành mở khóa địa chỉ IP:

### Cách 1: Gỡ khóa thủ công ngay lập tức (Khuyên dùng)
Tại terminal của **VM 2 (`192.168.1.20`)**, chạy:

```bash
sudo /var/ossec/active-response/bin/docker-firewall-drop delete - 192.168.1.10
```

*(Lệnh này vừa xóa rule trong iptables vừa ghi nhận vào file `/var/ossec/logs/active-responses.log`)*.

Hoặc gỡ trực tiếp qua lệnh iptables:
```bash
sudo iptables -D DOCKER-USER -s 192.168.1.10 -j DROP
```

### Cách 2: Chờ cơ chế Timeout tự động
Hệ thống đã cấu hình `<timeout>600</timeout>` (10 phút). Sau 10 phút kể từ thời điểm bị khóa, Wazuh Manager sẽ tự động phát lệnh `delete` tới Agent và IP sẽ được khôi phục quyền truy cập tự động.

### Kiểm tra lại kết nối sau khi mở khóa:
Từ **VM 1 (Kali Linux)**:
```bash
curl -I http://192.168.1.20/
```
> Trả về `HTTP/1.1 200 OK` (hoặc `302 Found`) bình thường!

---

## ✅ 8. BẢNG CHECKLIST NGHIỆM THU GIAI ĐOẠN 4

- [ ] **4.1** Kịch bản [`test-attacks.sh`](file:///d:/DOANHUUNGUYEN/HOCTAP/ĐẠI%20HỌC%20TẠI%20HỌC%20VIỆN%20HOÀNG%20GIA%20(%20PTIT%20)/DATN/wazuh-modsec-siem-lab/scripts/test-attacks.sh) chạy thành công từ VM 1 (Kali Linux).
- [ ] **4.2** Toàn bộ các đòn tấn công ở Phase 2 (SQLi, XSS, LFI, RCE) đều bị WAF chặn với mã `HTTP 403 Forbidden`.
- [ ] **4.3** Phase 3 gửi 5 đòn tấn công dồn dập vượt ngưỡng $\ge 8$ lần/60 giây và kích hoạt thành công **Rule 100110 (Level 14)**.
- [ ] **4.4** Chuỗi `DOCKER-USER` trên VM 2 tự động sinh rule `DROP all -- 192.168.1.10`.
- [ ] **4.5** Máy Kali Linux bị cô lập hoàn toàn (`curl --connect-timeout 3` báo `Connection timed out`).
- [ ] **4.6** File log `/var/ossec/logs/active-responses.log` trên VM 2 ghi nhận đầy đủ hành động `BLOCKED` và `UNBLOCKED`.
- [ ] **4.7** Wazuh Dashboard hiển thị đầy đủ trực quan các sự kiện theo nhóm `modsecurity` và mã kỹ thuật MITRE ATT&CK.
- [ ] **4.8** Mở khóa IP thành công bằng lệnh `docker-firewall-drop delete`.

---

## 🎯 KẾT LUẬN GIAI ĐOẠN 4
Giai đoạn 4 đã hoàn tất xuất sắc chu trình khép kín của một trung tâm điều hành an ninh mạng (SOC/SIEM):
$$\text{Attack (Kali)} \longrightarrow \text{Detect \& Block (WAF)} \longrightarrow \text{Ingest \& Analyze (SIEM)} \longrightarrow \text{Active Response (Auto Drop)}$$

Hệ thống đã đạt đầy đủ các tiêu chuẩn kỹ thuật để bảo vệ thành công đồ án tốt nghiệp!
