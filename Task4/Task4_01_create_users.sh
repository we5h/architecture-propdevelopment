#!/bin/bash
# =============================================================================
# Task4 — Скрипт 1: Создание пользователей в Kubernetes (Minikube)
# PropDevelopment — RBAC
#
# Метод: x509-сертификаты, подписанные CA кластера (стандарт для Minikube).
# Каждый пользователь идентифицируется полем CN (Common Name) в сертификате.
# Принадлежность к группе задаётся полем O (Organization) — именно по нему
# работают RoleBinding/ClusterRoleBinding с subjects.kind=Group.
# =============================================================================

set -euo pipefail

# Директория для хранения сгенерированных сертификатов и kubeconfig
OUTPUT_DIR="./k8s-users"
mkdir -p "${OUTPUT_DIR}"

# Путь к CA кластера Minikube (стандартное расположение)
CA_CERT="${HOME}/.minikube/ca.crt"
CA_KEY="${HOME}/.minikube/ca.key"

# Адрес API-сервера (получаем из текущего контекста minikube)
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# =============================================================================
# Функция создания пользователя
# Аргументы:
#   $1 — username (CN в сертификате)
#   $2 — group    (O в сертификате, используется в RoleBinding)
# =============================================================================
create_user() {
  local USERNAME="$1"
  local GROUP="$2"
  local USER_DIR="${OUTPUT_DIR}/${USERNAME}"
  mkdir -p "${USER_DIR}"

  echo "----------------------------------------------------------------------"
  echo "Создание пользователя: ${USERNAME} (группа: ${GROUP})"

  # 1. Генерация приватного ключа пользователя
  openssl genrsa -out "${USER_DIR}/${USERNAME}.key" 2048 2>/dev/null
  echo "  [✓] Сгенерирован приватный ключ"

  # 2. Генерация Certificate Signing Request (CSR)
  #    CN = имя пользователя, O = группа (используется Kubernetes для RBAC)
  openssl req -new \
    -key "${USER_DIR}/${USERNAME}.key" \
    -out "${USER_DIR}/${USERNAME}.csr" \
    -subj "/CN=${USERNAME}/O=${GROUP}" 2>/dev/null
  echo "  [✓] Сгенерирован CSR (CN=${USERNAME}, O=${GROUP})"

  # 3. Подпись сертификата CA кластера (срок действия — 365 дней)
  openssl x509 -req \
    -in "${USER_DIR}/${USERNAME}.csr" \
    -CA "${CA_CERT}" \
    -CAkey "${CA_KEY}" \
    -CAcreateserial \
    -out "${USER_DIR}/${USERNAME}.crt" \
    -days 365 2>/dev/null
  echo "  [✓] Сертификат подписан CA кластера (срок: 365 дней)"

  # 4. Формирование kubeconfig для пользователя
  local KUBECONFIG_FILE="${USER_DIR}/${USERNAME}-kubeconfig.yaml"

  kubectl config set-cluster minikube \
    --server="${API_SERVER}" \
    --certificate-authority="${CA_CERT}" \
    --embed-certs=true \
    --kubeconfig="${KUBECONFIG_FILE}" > /dev/null

  kubectl config set-credentials "${USERNAME}" \
    --client-certificate="${USER_DIR}/${USERNAME}.crt" \
    --client-key="${USER_DIR}/${USERNAME}.key" \
    --embed-certs=true \
    --kubeconfig="${KUBECONFIG_FILE}" > /dev/null

  kubectl config set-context "${USERNAME}-context" \
    --cluster=minikube \
    --user="${USERNAME}" \
    --kubeconfig="${KUBECONFIG_FILE}" > /dev/null

  kubectl config use-context "${USERNAME}-context" \
    --kubeconfig="${KUBECONFIG_FILE}" > /dev/null

  echo "  [✓] kubeconfig создан: ${KUBECONFIG_FILE}"
  echo "      Использование: KUBECONFIG=${KUBECONFIG_FILE} kubectl get pods"
}

# =============================================================================
# Создание пользователей
# Формат: create_user <username> <group>
#
# Группы соответствуют полю O в сертификате и используются в RoleBinding:
#   - viewers            → роль viewer
#   - developers         → роль developer
#   - devops-engineers   → роль devops-engineer
#   - security-auditors  → роль security-auditor (ClusterRole)
#   - cluster-admins     → роль cluster-admin (ClusterRole)
# =============================================================================

echo "======================================================================"
echo "PropDevelopment — Создание пользователей Kubernetes"
echo "======================================================================"

# Группа: viewers (инженеры по эксплуатации, аналитики)
create_user "ivan-petrov"     "viewers"           # Инженер по эксплуатации, домен ЖКУ
create_user "anna-smirnova"   "viewers"           # Аналитик BI

# Группа: developers (разработчики продуктовых команд)
create_user "dmitry-kozlov"   "developers"        # Разработчик, группа сервисов для клиентов
create_user "elena-volkova"   "developers"        # Разработчик, группа сервисов ЖКУ

# Группа: devops-engineers
create_user "sergey-novikov"  "devops-engineers"  # DevOps, платформенная команда
create_user "maria-ivanova"   "devops-engineers"  # DevOps, группа сервисов для клиентов

# Группа: security-auditors (специалист по ИБ)
create_user "alexey-morozov"  "security-auditors" # Специалист по ИБ (единственный в компании)

# Группа: cluster-admins (только платформенная команда)
create_user "platform-admin"  "cluster-admins"    # Старший DevOps, платформенная команда

echo ""
echo "======================================================================"
echo "Все пользователи созданы. Файлы сохранены в: ${OUTPUT_DIR}/"
echo ""
echo "Структура:"
ls -1 "${OUTPUT_DIR}/"
echo ""
echo "ВАЖНО: Приватные ключи (*.key) — чувствительные данные."
echo "       Не добавляйте директорию k8s-users/ в git-репозиторий."
echo "       Добавьте в .gitignore: k8s-users/"
echo "======================================================================"
