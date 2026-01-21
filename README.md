# Fail2ban Filters

This project contains custom filters and jails for **fail2ban**, designed to protect against massive attacks and suspicious access.
The configuration is modular and reusable thanks to the use of a `.env` file to define variables.

---

## 📂 Project structure example

```bash
fail2ban-filters/
├── .env                        # Environment variables (log paths, etc)
├── filters/                    # Custom filters
│   ├── nginx-access.conf
│   ├── ssh.conf
│   └── ...
├── jails/                      # Jails templates with variables
│   ├── nginx-access.tpl
│   ├── ssh.tpl
│   └── ...
├── nftables/f2b-structure.nft  # NFTables structure and persistence
├── actions/                    # Fail2ban actions templates with variables
│   ├── nginx-docker-block.tpl
│   └── ...
├── apply.sh                    # Deployment script
├── manager.sh                  # Fail2ban Filters Live Manager
└── nginx_cron_reloader.sh      # Nginx cron reloader to (un)ban in batches and avoid too many reloads when bans are added or removed
```

---

## ⚙️ Configuration

### 1. 🗺️ Define log paths and jails variables in `.env`

Example:

```env
NGINX_ACCESS_LOG=path/to/nginx-proxy/access.log
NGINX_ERROR_LOG=path/to/nginx-proxy/error.log
NGINX_CONTAINER_NAME=nginx-proxy
NGINX_BLACKLIST_FILE=path/to/nginx-proxy/config/blacklist.conf
NGINX_CLOUDFLARE_FILE=path/to/nginx-proxy/config/cloudflare_realip.conf
NGINX_RELOAD_TRIGGER_FILE=/tmp/nginx_reload_pending
```

### 2. 🚀 Deployment

Run the script:
```bash
./apply.sh
```

The script:
* Checks if .env exists and variables are defined.
* Copies filters to /etc/fail2ban/filter.d/.
* Substitutes variables in templates and generates jails in /etc/fail2ban/jail.d/.
* Restarts fail2ban and shows status.

### 3. 🔍 Verification

* List jails:
```bash
sudo fail2ban-client status
```

* View jail details:
```bash
sudo fail2ban-client status nginx-access
sudo fail2ban-client status nginx-error
```

Or use manager.sh script for convenience and interactive options:
```bash
./manager.sh
```

## 📂 Smart Mapping of Logs and Filters

The system uses an automatic naming convention to link Fail2ban filters with their corresponding log files defined in the environment. This allows analysis and testing scripts to be **completely dynamic**.

### 1\. Naming Convention
For a new filter to be detected by the helpers (`test-regex.sh` and `ip_analyzer.sh`), it must follow this rule:

1.  **Filter File:** It must be in the `filters/` folder with a `.conf` extension.
    *   _Example:_ `filters/apache-auth.conf`
2.  **Variable in** `.env`**:** It must match the filter name, converted to **UPPERCASE**, replacing hyphens with **underscores** and ending in `_LOG`.
    *   _Example:_ `APACHE_AUTH_LOG=/var/log/apache2/error.log`


### 2\. Automatic Analysis Logic
The `ip_analyzer.sh` script detects the log type based on the filter name:

*   **Error Logs:** If the filter name contains the word `error`, the script will look for the IP after the `client:` pattern (standard Nginx/Apache format).
*   **Access Logs:** For the rest of the filters, the script will extract the IP from the first column (standard access log format).


### 3\. Scalability Example
If you want to add protection for a **Redis** service:

1.  Create `filters/redis-server.conf`.
2.  Add `REDIS_SERVER_LOG=/var/log/redis/redis.log` to your `.env`.
3.  Done! The scripts' menus will automatically update with the new option.


* * *

## 🚀 Helpers Usage

| **Script** | **Purpose** |
| :--- | :--- |
| `apply.sh` | Deploys filters and generates final Jails from `.tpl`. |
| `manager.sh` | **Fail2ban Filters** Live Manager. |
| `nginx_cron_reloader.sh` | Reloads Nginx cron when bans are added or removed<br>(Add `NGINX_BLACKLIST_FILE` and `NGINX_RELOAD_TRIGGER_FILE` as volumes to nginx service if using Docker). |


### 📌 Notes

* Adjust maxretry, findtime and bantime according to the desired level of aggressiveness.
* You can add more filters and jails following the same structure.
* The .env allows reusing configurations in different servers without modifying the templates.
