#!/bin/bash
# =============================================================================
# Task5 — Скрипт 1: Развёртывание четырёх сервисов в namespace prop-sales
# PropDevelopment
# =============================================================================

set -euo pipefail

NAMESPACE="prop-sales"

echo "======================================================================"
echo "PropDevelopment — Развёртывание сервисов для Task5"
echo "Namespace: ${NAMESPACE}"
echo "======================================================================"

# Убедимся что namespace существует (создан в Task4)
kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1 || \
  kubectl create namespace "${NAMESPACE}"

echo ""
echo "Развёртывание подов..."

# 1. front-end
kubectl run front-end-app \
  --image=nginx \
  --labels role=front-end \
  --expose \
  --port 80 \
  --namespace="${NAMESPACE}"
echo "  [✓] front-end-app (role=front-end)"

# 2. back-end-api
kubectl run back-end-api-app \
  --image=nginx \
  --labels role=back-end-api \
  --expose \
  --port 80 \
  --namespace="${NAMESPACE}"
echo "  [✓] back-end-api-app (role=back-end-api)"

# 3. admin-front-end
kubectl run admin-front-end-app \
  --image=nginx \
  --labels role=admin-front-end \
  --expose \
  --port 80 \
  --namespace="${NAMESPACE}"
echo "  [✓] admin-front-end-app (role=admin-front-end)"

# 4. admin-back-end-api
kubectl run admin-back-end-api-app \
  --image=nginx \
  --labels role=admin-back-end-api \
  --expose \
  --port 80 \
  --namespace="${NAMESPACE}"
echo "  [✓] admin-back-end-api-app (role=admin-back-end-api)"

echo ""
echo "Ожидание готовности подов..."
kubectl wait pod \
  --for=condition=Ready \
  --selector='role in (front-end,back-end-api,admin-front-end,admin-back-end-api)' \
  --timeout=60s \
  --namespace="${NAMESPACE}"

echo ""
echo "======================================================================"
echo "Состояние подов:"
kubectl get pods -n "${NAMESPACE}" --show-labels

echo ""
echo "Состояние сервисов:"
kubectl get services -n "${NAMESPACE}"
echo "======================================================================"
echo ""
echo "⚠️  ВАЖНО: Если поды зависли в ContainerCreating — это нормально."
echo "   Причина: Calico (CNI-плагин) ещё инициализируется после старта кластера."
echo "   Подождите 3-5 минут и проверьте статус:"
echo ""
echo "   # Статус Calico:"
echo "   kubectl get pods -n kube-system | grep calico"
echo ""
echo "   # Статус наших подов:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "   Как только calico-node перейдёт в Running — поды запустятся автоматически."
echo "======================================================================"