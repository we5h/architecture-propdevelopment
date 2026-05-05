#!/bin/bash
# =============================================================================
# Task5 — Скрипт 2: Применение сетевых политик и проверка трафика
# PropDevelopment
# =============================================================================

set -euo pipefail

NAMESPACE="prop-sales"

echo "======================================================================"
echo "PropDevelopment — Применение сетевых политик"
echo "======================================================================"

# Применяем все политики из файла
kubectl apply -f non-admin-api-allow.yaml

echo ""
echo "Применённые политики:"
kubectl get networkpolicies -n "${NAMESPACE}"

# =============================================================================
# Проверка трафика
# Используем временный alpine-под для тестирования.
# wget с --timeout=2 быстро покажет есть ли доступ.
# =============================================================================

echo ""
echo "======================================================================"
echo "Проверка трафика между сервисами"
echo "======================================================================"

# --- ДОЛЖНЫ РАБОТАТЬ ---

echo ""
echo "✅ ТЕСТ 1: front-end → back-end-api (должен пройти)"
kubectl run "test-$RANDOM" \
  --rm -i --tty=false \
  --image=alpine \
  --namespace="${NAMESPACE}" \
  --labels="role=front-end" \
  --restart=Never \
  -- wget -qO- --timeout=2 http://back-end-api-app \
  && echo "  [✓] ДОСТУП ЕСТЬ" || echo "  [✗] НЕТ ДОСТУПА"

echo ""
echo "✅ ТЕСТ 2: admin-front-end → admin-back-end-api (должен пройти)"
kubectl run "test-$RANDOM" \
  --rm -i --tty=false \
  --image=alpine \
  --namespace="${NAMESPACE}" \
  --labels="role=admin-front-end" \
  --restart=Never \
  -- wget -qO- --timeout=2 http://admin-back-end-api-app \
  && echo "  [✓] ДОСТУП ЕСТЬ" || echo "  [✗] НЕТ ДОСТУПА"

# --- ДОЛЖНЫ БЫТЬ ЗАБЛОКИРОВАНЫ ---

echo ""
echo "🚫 ТЕСТ 3: front-end → admin-back-end-api (должен быть заблокирован)"
kubectl run "test-$RANDOM" \
  --rm -i --tty=false \
  --image=alpine \
  --namespace="${NAMESPACE}" \
  --labels="role=front-end" \
  --restart=Never \
  -- wget -qO- --timeout=2 http://admin-back-end-api-app \
  && echo "  [✗] ДОСТУП ЕСТЬ — политика не работает!" \
  || echo "  [✓] ЗАБЛОКИРОВАНО — правильно"

echo ""
echo "🚫 ТЕСТ 4: admin-front-end → back-end-api (должен быть заблокирован)"
kubectl run "test-$RANDOM" \
  --rm -i --tty=false \
  --image=alpine \
  --namespace="${NAMESPACE}" \
  --labels="role=admin-front-end" \
  --restart=Never \
  -- wget -qO- --timeout=2 http://back-end-api-app \
  && echo "  [✗] ДОСТУП ЕСТЬ — политика не работает!" \
  || echo "  [✓] ЗАБЛОКИРОВАНО — правильно"

echo ""
echo "🚫 ТЕСТ 5: back-end-api → admin-back-end-api (должен быть заблокирован)"
kubectl run "test-$RANDOM" \
  --rm -i --tty=false \
  --image=alpine \
  --namespace="${NAMESPACE}" \
  --labels="role=back-end-api" \
  --restart=Never \
  -- wget -qO- --timeout=2 http://admin-back-end-api-app \
  && echo "  [✗] ДОСТУП ЕСТЬ — политика не работает!" \
  || echo "  [✓] ЗАБЛОКИРОВАНО — правильно"

echo ""
echo "======================================================================"
echo "Итоговая схема трафика:"
echo ""
echo "  front-end  ←→  back-end-api          ✅ разрешено"
echo "  admin-front-end  ←→  admin-back-end-api  ✅ разрешено"
echo ""
echo "  front-end  →  admin-back-end-api     🚫 запрещено"
echo "  admin-front-end  →  back-end-api     🚫 запрещено"
echo "  back-end-api  →  admin-back-end-api  🚫 запрещено"
echo "======================================================================"
