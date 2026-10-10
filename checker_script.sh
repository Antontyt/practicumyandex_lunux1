#! /bin/bash
TARGET_SCRIPT=/opt/script.sh
TARGET_SCRIPT_LOG=/opt/my.log
SCRIPT_LOG=/var/log/checker_script.log
SCRIPT_VERSION=1.2

log() {
	# Функция для записи логов и вывода на экран
	# Версия 1.0.4
	local LEVEL=$1
	local MESSAGE=$2
	local TIME=$(date '+%H:%M:%S')
	echo $TIME $LEVEL $MESSAGE >> $SCRIPT_LOG
	echo $MESSAGE
}

check_log_growth() {
	# Функция сравнения размера файла в промежутке
	# Функция нужна для понимания работает ли программа и обновляется ли лог
	# Версия 1.0.9
	local LOG=$1
	local WAIT=${2:-3}     # интервал по умолчанию, 3 секунды

	# Проверяем существование файла
	if [ ! -f "$LOG" ]; then
		log ERROR "Лог $LOG не существует. Продолжение не возможно"
		return 1
	fi
	# Запоминаем размер файла
	local OLD_SIZE=$(stat -c %s "$LOG")
	sleep $WAIT
	# Проверяем если до сих пор файл
	if [ ! -f "$LOG" ]; then
		log ERROR "Лог $LOG не существует. Продолжение не возможно"
		return 1
	fi
	# Проверяем размер файла после WAIT
	local LAST_SIZE=$(stat -c %s "$LOG")
	if [ "$OLD_SIZE" != "$LAST_SIZE" ]; then
		log INFO "SIZE изменяется OLD_SIZE: $OLD_SIZE - LAST_SIZE: $LAST_SIZE"
		return 0
	else
		log ERROR "SIZE не изменился OLD_SIZE: $OLD_SIZE - LAST_SIZE: $LAST_SIZE"
		return 1
	fi
}

recover_deleted_script() {
	# Функция восстановления исходного кода скрипта, который продолжает
	# выполняться после удаления своего файла
	# Файл в UNIX живёт, пока открыт хотя бы одним процессом: rm убирает лишь
	# имя в каталоге. Bash держит файл скрипта открытым, поэтому содержимое
	# читается обратно через /proc/<PID>/fd/<N>.
	local SCRIPT=$1
	local FD_LINK FD_TARGET

	for FD_LINK in /proc/[0-9]*/fd/*; do
		FD_TARGET=$(readlink -- "$FD_LINK" 2>/dev/null)

		[ "$FD_TARGET" = "$SCRIPT (deleted)" ] || continue

		# Пишем прямо на место целевого файла
		if ! cat -- "$FD_LINK" > "$SCRIPT" 2>/dev/null; then
			rm -f "$SCRIPT"
			log ERROR "Найден $FD_LINK, но записать в $SCRIPT не удалось (нет прав?)"
			return 1
		fi

		# Пустой файл на месте рабочего скрипта не оставляем
		if [ ! -s "$SCRIPT" ]; then
			rm -f "$SCRIPT"
			continue
		fi

		chmod +x "$SCRIPT" 2>/dev/null
		log INFO "Исходный код восстановлен из $FD_LINK, размер $(stat -c %s "$SCRIPT") байт"
		return 0
	done

	log ERROR "Процесс, держащий открытым $SCRIPT (deleted), не найден"
	return 1
}

if [ -f "$SCRIPT_LOG" ]; then
	rm $SCRIPT_LOG
fi

log INFO "Скрипт проверки checker_script.sh v$SCRIPT_VERSION"
log INFO "Проверка наличия скрипта $TARGET_SCRIPT"
if [ -f "$TARGET_SCRIPT" ]; then
	log INFO "Файл $TARGET_SCRIPT обнаружен"
else
	log ERROR "Файл $TARGET_SCRIPT не обнаружен - запустите в ручную до этого скрипта"
	log ERROR "Скрипт завершён"
	exit 1
fi
log INFO "Проверка количества запущенных процессов скрипта $TARGET_SCRIPT"
PROC_COUNT=$(pgrep -c -f "/bin/bash $TARGET_SCRIPT")
if [ "$PROC_COUNT" -eq 0 ]; then
	log ERROR "Процесса нет. PROC_COUNT: $PROC_COUNT"
	log ERROR "Скрипт завершён"
	exit 1
elif [ "$PROC_COUNT" -eq 1 ]; then
	log INFO "Количество процессов: $PROC_COUNT"
else
	log ERROR "Количество процессов больше 1: $PROC_COUNT"
	log ERROR "Скрипт завершён"
	exit 1
fi
log INFO "Получение PID скрипта $TARGET_SCRIPT"
PID=$(pgrep -f "/bin/bash $TARGET_SCRIPT")
log INFO "Получен PID: $PID для процесса $TARGET_SCRIPT"

log INFO "Проверка жив ли процесс и идёт ли запись в лог"
if check_log_growth $TARGET_SCRIPT_LOG; then
	log INFO "Запись в лог ведётся"
else
	log ERROR "Скрипт завершён"
	exit 1
fi

log INFO "Удаляем скрипт $TARGET_SCRIPT"
if [ -f "$TARGET_SCRIPT" ]; then
	log INFO "Найден скрипт - выполняем удаление"
	rm $TARGET_SCRIPT
else
	log ERROR "Скрипт $TARGET_SCRIPT не найден"
	log ERROR "Скрипт завершён"
	exit 1
fi

log INFO "Проверяем удалён ли скрипт $TARGET_SCRIPT"
if [ ! -f "$TARGET_SCRIPT" ]; then
	log INFO "Удалён успешно - проверка пройдена"
else
	log ERROR "Скрипт $TARGET_SCRIPT найден"
	log ERROR "Скрипт завершён"
	exit 1
fi

log INFO "Проверка жив ли процесс и идёт ли запись в лог после удаления скрипта"
if check_log_growth $TARGET_SCRIPT_LOG; then
	log INFO "Запись в лог ведётся"
else
	log ERROR "Скрипт завершён"
	exit 1
fi

log INFO "Попытка восстановить исходный код из памяти процесса"
if recover_deleted_script "$TARGET_SCRIPT"; then
	log INFO "Восстановление удалось. Продолжаем проверки"
else
	log ERROR "Скрипт завершён"
	exit 1
fi

log INFO "Проверяем наличие скрипта $TARGET_SCRIPT после восстановления"
if [ -f "$TARGET_SCRIPT" ]; then
	log INFO "Скрипт после восстановления успешно найден"
else
	log ERROR "Скрипт $TARGET_SCRIPT не найден"
	log ERROR "Скрипт завершён"
	exit 1
fi