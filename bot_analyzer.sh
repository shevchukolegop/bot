#!/bin/bash

# Файл для результатів
OUTPUT_FILE="/root/bot-filter.txt"

# Очищення файлу результатів якщо він існує
> "$OUTPUT_FILE"

# Визначаємо дату 24 години тому у форматі логів Apache
DATE_24H_AGO=$(date -d "24 hours ago" "+%d/%b/%Y")

# Створюємо тимчасовий файл для підрахунку запитів ботів по сайтах
TEMP_COUNTS="/tmp/bot_site_counts.tmp"
> "$TEMP_COUNTS"

# Масив шляхів для пошуку лог-файлів
# Можна легко додавати нові шляхи або видаляти існуючі
LOG_PATHS=(
    "/var/log/apache2/domlogs/*/*-ssl_log"
    "/home/*/log/*-ssl_log"
    "/home/*/logs/*-ssl_log"
    "/var/log/httpd/domains/*-ssl_log"
    "/var/log/apache/domlogs/*/*-ssl_log"
    "/usr/local/apache/domlogs/*.log"
    "/var/log/nginx/domlogs/*/*-ssl_log"
)

echo "Аналізую логи за останні 24 години..."

# Перебираємо всі шляхи з масиву
for path_pattern in "${LOG_PATHS[@]}"; do
    # Видалені повідомлення про пошук логів
    
    # Розширюємо шаблон шляху в список файлів
    log_files=$(find ${path_pattern%/*} -path "$path_pattern" 2>/dev/null || echo "")
    
    # Перевіряємо, чи знайдені файли за цим шляхом
    if [ -z "$log_files" ]; then
        # Видалені повідомлення про відсутність логів
        continue
    fi
    
    # Обробляємо кожен знайдений лог-файл
    for log_file in $log_files; do
        # Перевіряємо, чи файл існує і є читабельним
        if [ ! -r "$log_file" ]; then
            # Видалені повідомлення про недоступність файлу
            continue
        fi
        
        # Отримуємо ім'я користувача з шляху до логу
        case "$log_file" in
            /var/log/apache2/domlogs/* | /var/log/apache/domlogs/* | /var/log/nginx/domlogs/*)
                user_name=$(echo "$log_file" | awk -F'/' '{print $(NF-1)}')
                ;;
            /home/*/log/* | /home/*/logs/*)
                user_name=$(echo "$log_file" | awk -F'/' '{print $3}')
                ;;
            /var/log/httpd/domains/*)
                user_name=$(basename $(dirname "$log_file"))
                ;;
            *)
                # Для інших шляхів використовуємо власника файлу
                user_name=$(stat -c '%U' "$log_file")
                ;;
        esac
        
        # Отримуємо назву сайту з лог-файлу
        site_name=$(basename "$log_file" | sed 's/-ssl_log//')
        
        # Підраховуємо запити від ботів за останні 24 години
        bot_requests_count=$(grep -i "$DATE_24H_AGO" "$log_file" | grep -i -E "(bot|crawler|spider|facebook|meta)" | wc -l)
        
        # Зберігаємо результат для сортування
        if [ "$bot_requests_count" -gt 0 ]; then
            echo "$user_name:$log_file:$bot_requests_count" >> "$TEMP_COUNTS"
        fi
    done
done

# Перевіряємо, чи є записи в тимчасовому файлі
if [ ! -s "$TEMP_COUNTS" ]; then
    echo "Не знайдено запитів від ботів за останні 24 години."
    echo "Не знайдено запитів від ботів за останні 24 години." > "$OUTPUT_FILE"
    rm -f "$TEMP_COUNTS"
    exit 0
fi

# Сортуємо сайти за кількістю запитів від ботів (у порядку спадання)
sort -t':' -k3 -nr "$TEMP_COUNTS" > "${TEMP_COUNTS}.sorted"

# Записуємо заголовок у результуючий файл
echo "=== СТАТИСТИКА ЗАПИТІВ ВІД БОТІВ ЗА ОСТАННІ 24 ГОДИНИ ===" > "$OUTPUT_FILE"
echo "Дата аналізу: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Виводимо статистику по сайтах з топ-5 ботами для кожного сайту
echo "=== САЙТИ З НАЙБІЛЬШОЮ КІЛЬКІСТЮ ЗАПИТІВ ВІД БОТІВ ===" >> "$OUTPUT_FILE"
while IFS=':' read -r user_name log_file bot_count; do
    echo "Користувач: $user_name" >> "$OUTPUT_FILE"
    echo "Лог-файл: $log_file" >> "$OUTPUT_FILE"
    echo "Кількість запитів від ботів: $bot_count" >> "$OUTPUT_FILE"

    # Створюємо тимчасовий файл для агрегації ботів
    BOT_AGGREGATION="/tmp/bot_aggregation.tmp"
    > "$BOT_AGGREGATION"

    # Отримуємо всі User-Agent'и ботів і підраховуємо їх частоту
    grep -i "$DATE_24H_AGO" "$log_file" | grep -i -E "(bot|crawler|spider|developers|facebook|meta|alibaba)" |
    grep -o -E '"[^"]+"$' | tr -d '"' | while read -r user_agent; do
        # Спрощуємо назву бота для більш чіткого представлення
        bot_name=$(echo "$user_agent" | grep -o -i -E "[a-zA-Z0-9]+[Bb]ot|[a-zA-Z0-9]+[Cc]rawler|[a-zA-Z0-9]+[Ss]pider" | head -1)

        # Якщо не вдалося знайти стандартну назву, використовуємо перші 50 символів User-Agent
        if [ -z "$bot_name" ]; then
            bot_name=$(echo "$user_agent" | cut -c 1-50)
            # Додаємо "..." якщо обрізали
            if [ ${#user_agent} -gt 50 ]; then
                bot_name="${bot_name}..."
            fi
        fi

        # Додаємо бота в файл агрегації
        echo "$bot_name" >> "$BOT_AGGREGATION"
    done

    # Підраховуємо та сортуємо ботів
    echo "Топ-5 ботів для цього сайту:" >> "$OUTPUT_FILE"
    sort "$BOT_AGGREGATION" | uniq -c | sort -nr | head -5 | while read -r count bot_name; do
        echo "  - $bot_name - $count запитів" >> "$OUTPUT_FILE"
    done

    # Видаляємо тимчасовий файл
    rm -f "$BOT_AGGREGATION"

    echo "-----------------------------------------" >> "$OUTPUT_FILE"
done < "${TEMP_COUNTS}.sorted"

# Виводимо загальну статистику
total_bots=$(awk -F: '{sum += $3} END {print sum}' "${TEMP_COUNTS}.sorted")
total_sites=$(wc -l < "${TEMP_COUNTS}.sorted")

echo "" >> "$OUTPUT_FILE"
echo "=== ЗАГАЛЬНА СТАТИСТИКА ===" >> "$OUTPUT_FILE"
echo "Загальна кількість запитів від ботів: $total_bots" >> "$OUTPUT_FILE"
echo "Кількість сайтів з активністю ботів: $total_sites" >> "$OUTPUT_FILE"

# Видаляємо тимчасові файли
rm -f "$TEMP_COUNTS" "${TEMP_COUNTS}.sorted"

echo "" >> "$OUTPUT_FILE"
echo "Аналіз завершено. Результати збережено в $OUTPUT_FILE або натисніть \"Show results\" чи \"Top in results\""
