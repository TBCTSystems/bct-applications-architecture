# Hosts File Requirements - Certificate Management PoC

## 🎯 **Current System Analysis**

After analyzing the docker-compose.yml and current implementation, here are the **actual** hosts file requirements:

## ✅ **Required Hosts File Entries**

Based on the current docker-compose.yml configuration:

```
# Certificate Management PoC - Local Domain Resolution
127.0.0.1 ca.localtest.me
127.0.0.1 device.localtest.me
127.0.0.1 app.localtest.me
127.0.0.1 mqtt.localtest.me
```

## 🔍 **Analysis of Current Configuration**

### **step-ca Certificate Authority**
- **Container hostname**: `stepca.local`
- **DNS names in certificate**: `ca.localtest.me,stepca.local,localhost`
- **External access**: `https://ca.localtest.me:9000`
- **Required hosts entry**: ✅ `127.0.0.1 ca.localtest.me`

### **Certbot Containers**
- **certbot-device**: Uses `device.localtest.me` for ACME challenges
- **certbot-app**: Uses `app.localtest.me` for ACME challenges  
- **certbot-mqtt**: Uses `mqtt.localtest.me` for ACME challenges
- **Required hosts entries**: ✅ All three domains above

### **Other Services (Internal Only)**
- **mosquitto**: `hostname: mqtt.local` (internal Docker network only)
- **grafana**: `hostname: grafana.local` (internal Docker network only)
- **loki**: `hostname: loki.local` (internal Docker network only)
- **Required hosts entries**: ❌ **NOT NEEDED** (accessed via localhost ports)

## 🚨 **Documentation Inconsistencies Found**

### **Current Issues**
1. **setup.sh** includes `grafana.localtest.me` - ❌ **NOT NEEDED**
2. **setup.ps1** includes `grafana.localtest.me` - ❌ **NOT NEEDED**
3. **docs/setup-guide.md** includes several `.local` domains - ❌ **NOT NEEDED**
4. **Scripts reference wrong domains** - Need updating

### **What's Actually Needed vs. What's Documented**

| Service | Current Docs Say | Actually Needed | Reason |
|---------|------------------|-----------------|---------|
| step-ca | `stepca.local` | `ca.localtest.me` | External ACME access |
| Device certs | `device.local` | `device.localtest.me` | ACME challenge domain |
| App certs | `app.local` | `app.localtest.me` | ACME challenge domain |
| MQTT certs | `mqtt.local` | `mqtt.localtest.me` | ACME challenge domain |
| Grafana | `grafana.local` | ❌ None | Access via localhost:3000 |
| Loki | ❌ None | ❌ None | Access via localhost:3100 |
| Mosquitto | ❌ None | ❌ None | Access via localhost:1883/8883 |

## ✅ **Corrected Hosts File Entries**

### **Minimal Required Configuration**
```
# Certificate Management PoC - ACME Domain Resolution
127.0.0.1 ca.localtest.me
127.0.0.1 device.localtest.me
127.0.0.1 app.localtest.me
127.0.0.1 mqtt.localtest.me
```

### **Why These Domains Are Needed**

1. **ca.localtest.me**: 
   - step-ca ACME directory endpoint
   - Certificate authority health checks
   - Root certificate download

2. **device.localtest.me**:
   - ACME HTTP-01 challenge validation
   - Device certificate issuance

3. **app.localtest.me**:
   - ACME HTTP-01 challenge validation  
   - Application certificate issuance

4. **mqtt.localtest.me**:
   - ACME HTTP-01 challenge validation
   - MQTT broker certificate issuance

### **Why Other Domains Are NOT Needed**

1. **grafana.local**: Grafana is accessed via `http://localhost:3000`
2. **loki.local**: Loki is accessed via `http://localhost:3100`  
3. **mqtt.local**: Mosquitto is accessed via `localhost:1883/8883`
4. **device.local**: Wrong domain - should be `device.localtest.me`

## 🔧 **Required Updates**

### **Files That Need Updating**
1. **setup.sh** - Remove `grafana.localtest.me`, fix domain names
2. **setup.ps1** - Remove `grafana.localtest.me`, fix domain names
3. **docs/setup-guide.md** - Update hosts file section
4. **README.md** - Update quick start section
5. **All documentation** - Standardize on correct domains

### **Verification Commands**
```bash
# Test required domains
ping ca.localtest.me
ping device.localtest.me  
ping app.localtest.me
ping mqtt.localtest.me

# Test ACME endpoint
curl -k https://ca.localtest.me:9000/acme/acme/directory

# Test service access (no hosts entries needed)
curl http://localhost:3000/api/health  # Grafana
curl http://localhost:3100/ready       # Loki
```

## 📋 **Action Items**

1. ✅ **Document the correct requirements** (this file)
2. ⏳ **Update setup.sh** - Fix domain list
3. ⏳ **Update setup.ps1** - Fix domain list  
4. ⏳ **Update docs/setup-guide.md** - Correct hosts file section
5. ⏳ **Update README.md** - Fix quick start
6. ⏳ **Test all scripts** - Verify they work with correct domains

## 🎯 **Summary**

**Only 4 hosts file entries are actually needed:**
- `ca.localtest.me` (step-ca ACME access)
- `device.localtest.me` (device certificate ACME challenges)
- `app.localtest.me` (app certificate ACME challenges)  
- `mqtt.localtest.me` (MQTT certificate ACME challenges)

All other services are accessed via localhost ports and don't need hosts file entries.