#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}=== Fail2ban Filters Live Manager ===${NC}"
echo -e "${CYAN}=====================================${NC}\n"

jails_list=$(sudo fail2ban-client status | grep 'Jail list' | sed 's/.*Jail list://' | tr -d ',')
read -a active_jails <<< "$jails_list"

if [ ${#active_jails[@]} -eq 0 ]; then
    echo -e "${RED}❌ No active jails found. Check if fail2ban is running.${NC}"
    exit 1
fi

menu_options() {
    echo -e "${YELLOW}--- Active Jails Top 10 IPs ---${NC}"
    for i in "${!active_jails[@]}"; do
        echo -e "${GREEN}$((i+1)))${NC} ${active_jails[$i]}"
    done
    echo -e "\n${YELLOW}--- Manual Actions ---${NC}"
    echo -e "${GREEN}B)${NC} Ban IP manually"
    echo -e "${GREEN}U)${NC} Unban IP manually"
    echo -e "${GREEN}C)${NC} Count banned IPs for all Jails"
    echo -e "${GREEN}D)${NC} Detailed list of banned IPs for all Jails"
    echo -e "${GREEN}E)${NC} Export banned IPs to .txt files"
    echo -e "${GREEN}I)${NC} Import banned IPs from .txt files"
    echo -e "${GREEN}N)${NC} NFTables bans list"
    echo -e "${GREEN}R)${NC} Restart Fail2ban"
    echo -e "${GREEN}S)${NC} Search IP in banned lists"
    echo -e "${GREEN}T)${NC} Test Fail2ban filters"
    echo -e "${GREEN}X)${NC} Exit"
}

menu_options
echo -e "${GREEN}"
read -p "Select option: " opt
echo -e "${NC}"

if [[ "$opt" =~ ^[0-9]+$ ]] && [ "$opt" -le "${#active_jails[@]}" ]; then
    jail_name=${active_jails[$((opt-1))]}
    raw_output=$(sudo fail2ban-client get "$jail_name" logpath | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g")

    if [[ "$raw_output" == *"No file(s) found"* ]]; then
        echo -e "\n${YELLOW}Jail [$jail_name] uses systemd journal.${NC}"
        echo -e "${CYAN}Extracting Top 10 IPs (last 24 hours)...${NC}"
        sudo journalctl -u "$jail_name" --since "24 hours ago" --no-pager | grep -oP "\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b" | sort | uniq -c | sort -nr | head -n 10
    else
        log_file=$(echo "$raw_output" | sed 's/Current monitored log file(s)://g' | tr -d '`|' | sed 's/^-//g' | xargs -n1 2>/dev/null | head -n1)
        
        if [ -n "$log_file" ] && sudo test -f "$log_file"; then
            echo -e "\n${YELLOW}Analyzing [$jail_name]:${NC} $log_file"
            echo -e "${CYAN}Top 10 IPs attempting access:${NC}"
            sudo awk '{print $1}' "$log_file" | grep -E '([0-9]{1,3}\.){3}|([a-f0-9:]+:+)+' | sort | uniq -c | sort -nr | head -n 10
        else
            echo -e "${YELLOW}Analyzing [$jail_name]:${NC} journalctl"
            echo -e "${CYAN}Top 10 IPs attempting access:${NC}"
            sudo journalctl -t "$jail_name" --since "24 hours ago" --no-pager | grep -oP "\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b" | sort | uniq -c | sort -nr | head -n 10
        fi
    fi

elif [[ "$opt" == "b" || "$opt" == "B" ]]; then
    read -p "IP to ban: " ip
    [[ -z "$ip" ]] && echo "Cancelled." && exit
    echo -e "${YELLOW}Available jails:${NC} ${active_jails[@]}"
    read -p "Jail Name: " jail
    sudo fail2ban-client set "$jail" banip "$ip" && echo -e "${GREEN}✅ IP $ip banned.${NC}"

elif [[ "$opt" == "u" || "$opt" == "U" ]]; then
    read -p "IP to unban: " ip
    [[ -z "$ip" ]] && echo "Cancelled." && exit
    echo -e "${YELLOW}Available jails:${NC} ${active_jails[@]}"
    read -p "Jail Name: " jail
    sudo fail2ban-client set "$jail" unbanip "$ip" && echo -e "${GREEN}✅ IP $ip unbanned.${NC}"

elif [[ "$opt" == "c" || "$opt" == "C" ]]; then
    for jail in "${active_jails[@]}"; do
        status=$(sudo fail2ban-client status "$jail" | grep "Currently banned" | sed 's/^[ \t]*//')
        echo -e "${CYAN}Jail:${NC} ${GREEN}$(printf '%-15s' "$jail")${NC} -> $status"
    done

elif [[ "$opt" == "d" || "$opt" == "D" ]]; then
    echo -e "\n${CYAN}=== Detailed list of banned IPs for all Fail2ban Jails ===${NC}"
    for jail in "${active_jails[@]}"; do
        echo -e "${GOLD}──────────────────────────────────────────────────${NC}"
        echo -e "JAIL: ${CYAN}$jail${NC}"
        stats=$(sudo fail2ban-client status "$jail")
        
        echo "$stats" | grep -E "Currently failed:|Total failed:|Currently banned:|Total banned:"
        
        banned_ips=$(echo "$stats" | grep "Banned IP list:" | sed 's/.*Banned IP list://' | xargs)
        if [ -n "$banned_ips" ]; then
            echo -e "Currently banned IPs: ${GREEN}${banned_ips}${NC}"
        else
            echo -e "Currently banned IPs: ${RED}None${NC}"
        fi
    done
    echo -e "${GOLD}──────────────────────────────────────────────────${NC}"

elif [[ "$opt" == "n" || "$opt" == "N" ]]; then
    echo -e "${BLUE}=== Status of bans in NFTables ===${NC}"

    echo -e "\n${GREEN}➡️  Currently banned IPs:${NC}"
    sudo nft -a list sets | grep -E "set (f2b-|addr-set-|addr6-set-)" || echo "No active IP sets found."

    if sudo nft list table inet f2b-table &>/dev/null; then
        echo -e "\n${GREEN}➡️  Fail2ban rules details (f2b-table):${NC}"
        sudo nft -a list table inet f2b-table
    else
        echo -e "\n${BLUE}ℹ️  The 'f2b-table' table has not been created yet.${NC}"
        echo "This is normal if there have been no bans yet."
    fi

    if [ "$1" == "--all" ]; then
        echo -e "\n${BLUE}=== Complete Ruleset ===${NC}"
        sudo nft -a list ruleset
    fi

elif [[ "$opt" == "r" || "$opt" == "R" ]]; then
    echo -e "${GREEN}🔄 Restarting Fail2ban...${NC}"
    sudo systemctl restart fail2ban
    echo -e "${GREEN}✅ Fail2ban restarted.${NC}"

elif [[ "$opt" == "s" || "$opt" == "S" ]]; then
    read -p "Enter IP or list of IPs (separated by commas): " input_ips
    [[ -z "$input_ips" ]] && echo "Cancelled." && exit
    IFS=',' read -ra ADDR <<< "$input_ips"

    for ip in "${ADDR[@]}"; do
        ip=$(echo "$ip" | xargs)
        [[ -z "$ip" ]] && continue
        echo -e "\n${CYAN}🔎 Searching for IP:${NC} ${YELLOW}$ip${NC}"
        echo -e "${CYAN}--------------------------------------------------${NC}"

        found_any=false

        for jail in "${active_jails[@]}"; do
            is_banned=$(sudo fail2ban-client status "$jail" | grep "Banned IP list:" | grep -qE "\b$ip\b" && echo -e "${RED}[BANNED]${NC}" || echo -e "${GREEN}[CLEAN]${NC}")
            raw_output=$(sudo fail2ban-client get "$jail" logpath | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g")

            echo -e "Jail: ${CYAN}$(printf '%-15s' "$jail")${NC} State: $is_banned"

            logs=""

            if [[ "$raw_output" == *"No file(s) found"* ]]; then
                logs=$(sudo journalctl -u "$jail" --since "48 hours ago" --no-pager | grep "$ip")
            else
                log_file=$(echo "$raw_output" | sed 's/Current monitored log file(s)://g' | tr -d '`|' | sed 's/^-//g' | xargs -n1 2>/dev/null | head -n1)
                if [ -n "$log_file" ] && [ -f "$log_file" ]; then
                    logs=$(sudo grep "$ip" "$log_file" 2>/dev/null)
                fi
            fi

            if [ -n "$logs" ]; then
                count=$(echo "$logs" | wc -l)
                echo -e "   └─ Matches: ${YELLOW}$count${NC} times"

                echo "$logs" | grep -oP '\s[1-5][0-9]{2}\s' | sed 's/ //g' | sort | uniq -c | sort -nr | while read -r line; do
                    occ=$(echo $line | awk '{print $1}')
                    code=$(echo $line | awk '{print $2}')
                    echo -e "      ${GREEN}→${NC} Code ${CYAN}$code${NC}: $occ"
                done

                found_any=true
            else
                echo -e "   └─ No recent logs found."
            fi
        done

        if [ "$found_any" = false ]; then
            echo -e "${RED}⚠️  No traces of the IP found in active jails.${NC}"
        fi
    done

elif [[ "$opt" == "t" || "$opt" == "T" ]]; then
    ENV_FILE="./.env"
    [ -f "$ENV_FILE" ] && export $(grep -v '^#' "$ENV_FILE" | xargs -d '\n' | tr -d '\r')

    echo -e "${CYAN}=== Dynamic Regex Tester ===${NC}"

    filters=($(ls filters/*.conf 2>/dev/null | xargs -n 1 basename | sed 's/.conf//'))

    if [ ${#filters[@]} -eq 0 ]; then
        echo "❌ No filters found in filters/ folder"
        exit 1
    fi

    echo -e "${YELLOW}Select a filter to test:${NC}"
    for i in "${!filters[@]}"; do
        echo -e "${GREEN}$((i+1)))${NC} ${filters[$i]}"
    done
    echo -e "${GREEN}$(( ${#filters[@]} + 1 )))${NC} Exit"

    echo -e "${GREEN}"
    read -p "Select option: " opt
    echo -e "${NC}"

    if [[ "$opt" -gt 0 && "$opt" -le "${#filters[@]}" ]]; then
        filter_name=${filters[$((opt-1))]}

        var_name=$(echo "${filter_name}_LOG" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        log_path="${!var_name}"

        if [ -z "$log_path" ]; then
            echo -e "${RED}❌ Error: No variable $var_name found in .env${NC}"
            exit 1
        fi

        echo -e "\n${YELLOW}Testing:${NC} $filter_name | ${YELLOW}Log:${NC} $log_path"
        echo -e "1) Summary\n2) Matched\n3) Missed"
        read -p "Detail: " detail

        case $detail in
            1) sudo fail2ban-regex "$log_path" "./filters/${filter_name}.conf" ;;
            2) sudo fail2ban-regex --print-all-matched "$log_path" "./filters/${filter_name}.conf" ;;
            3) sudo fail2ban-regex --print-all-missed "$log_path" "./filters/${filter_name}.conf" ;;
        esac
    else
        exit 0
    fi

elif [[ "$opt" == "e" || "$opt" == "E" ]]; then
    EXPORT_DIR="$SCRIPT_DIR/exports"
    mkdir -p "$EXPORT_DIR"
    echo -e "${YELLOW}Exporting IPs to: $EXPORT_DIR${NC}"

    for jail in "${active_jails[@]}"; do
        banned_ips=$(sudo fail2ban-client status "$jail" | grep "Banned IP list:" | sed 's/.*Banned IP list://' | tr -d ',')

        if [ -z "$(echo $banned_ips | xargs)" ]; then
            echo -e "Jail ${CYAN}$jail${NC}: No IPs to export."
        else
            EXPORT_DATE=$(date +%Y%m%d_%H%M%S)
            echo "$banned_ips" | xargs -n1 > "$EXPORT_DIR/${jail}_banned_$EXPORT_DATE.txt"
            count=$(wc -l < "$EXPORT_DIR/${jail}_banned_$EXPORT_DATE.txt")
            echo -e "Jail ${CYAN}$jail${NC}: ${GREEN}$count IPs${NC} exported to ${jail}_banned_$EXPORT_DATE.txt"
        fi
    done
    echo -e "\n${GREEN}✅ Export completed.${NC}"

elif [[ "$opt" == "i" || "$opt" == "I" ]]; then
    EXPORT_DIR="$SCRIPT_DIR/exports"

    files=($(ls "$EXPORT_DIR"/*.txt 2>/dev/null))
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}❌ No .txt files found in $EXPORT_DIR${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Select file to import:${NC}"
    for i in "${!files[@]}"; do
        echo -e "${GREEN}$((i+1)))${NC} $(basename "${files[$i]}")"
    done
    read -p "Option: " file_opt
    selected_file="${files[$((file_opt-1))]}"

    if [ ! -f "$selected_file" ]; then echo "Invalid selection"; exit 1; fi

    echo -e "\n${YELLOW}Select destination Jail:${NC}"
    for i in "${!active_jails[@]}"; do
        echo -e "${GREEN}$((i+1)))${NC} ${active_jails[$i]}"
    done
    read -p "Option: " jail_opt
    target_jail="${active_jails[$((jail_opt-1))]}"

    if [ -z "$target_jail" ]; then echo "Invalid jail"; exit 1; fi

    echo -e "${CYAN}Importing IPs from $(basename "$selected_file") into [$target_jail]...${NC}"

    count=0
    while IFS= read -r ip; do
        ip=$(echo "$ip" | xargs)
        if [[ -n "$ip" ]]; then
            sudo fail2ban-client set "$target_jail" banip "$ip" > /dev/null 2>&1
            ((count++))
            echo -ne "Progress: $count IPs processed...\r"
        fi
    done < "$selected_file"

    echo -e "\n${GREEN}✅ Success: $count IPs processed in [$target_jail].${NC}"
    echo -e "${YELLOW}Note: IPs already banned were skipped.${NC}"

else
    echo -e "${CYAN}Exiting...${NC}"
    exit 0
fi
