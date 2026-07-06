# Restore a service from the NAS backup into the k8s 'restore' namespace (Test-Restore)
# Orchestriert vom Laptop: NAS pusht die Daten (server-initiiert), kubectl baut den
# Restore-Stack im Cluster. Der NAS bekommt KEINEN Cluster-Zugriff.
# Siehe talos-k8s/restore/README.md.
restore_k8s() {
    if [[ "${1:-}" == "-h" ]] || [[ -z "${1:-}" ]]; then
        echo "Restore a service from the NAS backup into k8s (Test- oder Prod-Restore)"
        echo "Usage: restore_k8s <app> [archive]          (Test -> 'restore' NS + Test-URL)"
        echo "       restore_k8s --prod <app> [archive]   (PROD -> echter NS, DESTRUKTIV)"
        echo "       restore_k8s list [app]"
        echo "       restore_k8s clean                    (Test-NS komplett loeschen)"
        echo "       restore_k8s clean --prod <app>       (nur Prod-Runner-Job + SSH-Key entfernen)"
        echo ""
        echo "  list               List available services on NAS (host k8s)"
        echo "  list <app>         List archives for an app"
        echo "  clean              Delete the whole 'restore' namespace"
        echo "  --prod <app>       PROD-Restore mit Safeguards (Snapshot, scale-down/up, Dry-run+Confirm)"
        echo "  <app>              App to restore (paperless, paperless-hbtest, nextcloud)"
        echo "  [archive]          Specific archive name (default: latest)"
        echo ""
        echo "Example: restore_k8s paperless"
        echo "         restore_k8s --prod paperless"
        echo "         restore_k8s list paperless"
        [[ -z "${1:-}" ]] && return 1 || return 0
    fi

    local NAS_SCRIPT="/mnt/backup/recovery/scripts/restore-push.sh"
    local NAS_HOST="k8s"
    local REPO="${TALOS_REPO:-$HOME/repos/talos-k8s}"
    local NS="restore"

    # List mode
    if [[ "$1" == "--list" ]] || [[ "$1" == "list" ]] || [[ "$1" == "-l" ]]; then
        local filter="${2:-}"
        echo ">>> NAS: Archive auflisten..."
        ssh nas "sudo -u recovery ${NAS_SCRIPT} --list ${NAS_HOST} ${filter}"
        return $?
    fi

    # Prod-Restore mode (eigene Orchestrierung mit Safeguards)
    if [[ "$1" == "--prod" ]]; then
        _restore_k8s_prod "${2:-}" "${3:-}"
        return $?
    fi

    # Clean mode
    if [[ "$1" == "clean" ]]; then
        # Prod-Cleanup: nur Runner-Job + SSH-Key im Prod-NS entfernen, NICHT den Namespace.
        if [[ "${2:-}" == "--prod" ]]; then
            local capp="${3:-}"
            local proddir="${REPO}/restore/${capp}/prod"
            [[ -n "$capp" && -f "${proddir}/profile.env" ]] || {
                echo "FEHLER: Usage: restore_k8s clean --prod <app>"; return 1; }
            local PROD_NAMESPACE; source "${proddir}/profile.env"
            echo ">>> Prod-Cleanup '${capp}' in NS '${PROD_NAMESPACE}'..."
            kubectl -n "$PROD_NAMESPACE" delete job "${capp}-prod-restore-runner" --ignore-not-found
            kubectl -n "$PROD_NAMESPACE" delete job "${capp}-prod-restore-inspect" --ignore-not-found
            kubectl -n "$PROD_NAMESPACE" delete secret restore-runner-ssh-key --ignore-not-found
            echo "    (Pre-Restore-VolumeSnapshots bleiben erhalten - 'kubectl -n ${PROD_NAMESPACE} get volumesnapshot')"
            return 0
        fi
        echo -n "Namespace '${NS}' komplett loeschen? (yes/no): "
        read -r confirm
        [[ "$confirm" == "yes" ]] || { echo "Abgebrochen."; return 1; }
        kubectl delete namespace "$NS" --ignore-not-found
        echo ">>> /etc/hosts: Restore-Eintraege entfernen (sudo)..."
        sudo sed -i '' '/# restore_k8s$/d' /etc/hosts 2>/dev/null \
            && echo "    entfernt" || echo "    (nichts zu entfernen / sudo abgelehnt)"
        return 0
    fi

    local app="$1"
    local archive="${2:-}"
    local appdir="${REPO}/restore/${app}"

    if [[ ! -d "$appdir" ]]; then
        echo "FEHLER: kein Restore-Overlay unter ${appdir}"
        return 1
    fi

    # App-spezifische Parameter. secret_kind steuert die Form des Laufzeit-Secrets
    # weiter unten (paperless-ngx-Charts vs. nextcloud-Chart brauchen unterschiedliche
    # Keys/Value-Shapes).
    local app_deploy secret_name secret_kind
    case "$app" in
        paperless)
            app_deploy="paperless-ngx"
            secret_name="paperless-restore-secrets"
            secret_kind="paperless"
            ;;
        paperless-hbtest)
            # Helm-Fullname bei abweichendem Release-/Chart-Namen: <release>-<chart>
            # (bestaetigt via kubectl in hb-test: deployment/paperless-hbtest-paperless-ngx)
            app_deploy="paperless-hbtest-paperless-ngx"
            secret_name="paperless-hbtest-restore-secrets"
            secret_kind="paperless"
            ;;
        nextcloud)
            app_deploy="nextcloud"
            secret_name="nextcloud-restore-secrets"
            secret_kind="nextcloud"
            ;;
        *)
            echo "FEHLER: App '${app}' noch nicht unterstuetzt (paperless, paperless-hbtest, nextcloud)"
            return 1
            ;;
    esac

    echo "========================================"
    echo "  Test-Restore '${app}' -> Namespace '${NS}'"
    echo "========================================"
    echo -n "Fortfahren? (yes/no): "
    read -r confirm
    [[ "$confirm" == "yes" ]] || { echo "Abgebrochen."; return 1; }

    # Step 1: NAS pusht die Restore-Daten (server-initiiert)
    echo ""
    echo ">>> NAS: Restore-Daten extrahieren und pushen..."
    ssh nas "sudo -u recovery ${NAS_SCRIPT} ${NAS_HOST} ${app} ${archive}"
    local push_rc=$?
    if [[ $push_rc -ne 0 ]]; then
        echo "FEHLER: restore-push auf NAS fehlgeschlagen (exit ${push_rc})"
        return 1
    fi

    # Step 2: Namespace + Runner-Key (SOPS) + Laufzeit-Secret
    echo ""
    echo ">>> k8s: Namespace + Secrets..."
    kubectl apply -f "${REPO}/restore/namespace.yaml" || return 1
    sops -d "${REPO}/restore/runner-ssh-key.sops.yaml" | kubectl apply -f - || {
        echo "FEHLER: runner-ssh-key konnte nicht angewandt werden (SOPS/age?)"; return 1; }

    if ! kubectl -n "$NS" get secret "$secret_name" >/dev/null 2>&1; then
        echo "    Erzeuge Laufzeit-Secret ${secret_name}..."
        local pw sk
        pw=$(openssl rand -hex 24)
        case "$secret_kind" in
            paperless)
                sk=$(openssl rand -hex 50)
                kubectl -n "$NS" create secret generic "$secret_name" \
                    --from-literal=POSTGRES_PASSWORD="$pw" \
                    --from-literal=PAPERLESS_DBPASS="$pw" \
                    --from-literal=PAPERLESS_SECRET_KEY="$sk" || return 1
                ;;
            nextcloud)
                # 'values' wird per valuesFrom in die HelmRelease gemergt
                # (externalDatabase.password) - siehe restore/nextcloud/helmrelease.yaml.
                kubectl -n "$NS" create secret generic "$secret_name" \
                    --from-literal=POSTGRES_PASSWORD="$pw" \
                    --from-literal=values="externalDatabase:
  password: \"${pw}\"
" || return 1
                ;;
        esac
    else
        echo "    Secret ${secret_name} existiert bereits (wiederverwenden)."
    fi

    # Step 3: Daten-Layer (PVCs + eigenstaendige Postgres)
    echo ""
    echo ">>> k8s: Daten-Layer (PVCs + Postgres)..."
    kubectl apply -f "${appdir}/pvcs.yaml" -f "${appdir}/db.yaml" || return 1
    echo "    Warte auf Postgres..."
    kubectl -n "$NS" rollout status "deploy/${app}-restore-db" --timeout=180s || return 1

    # Step 4: Restore-Runner (Dateien + DB laden)
    echo ""
    echo ">>> k8s: Restore-Runner (rsync + DB-Load)..."
    kubectl -n "$NS" delete job "${app}-restore-runner" --ignore-not-found
    kubectl apply -f "${appdir}/restore-runner-job.yaml" || return 1
    if ! kubectl -n "$NS" wait --for=condition=complete "job/${app}-restore-runner" --timeout=1h; then
        echo "FEHLER: Restore-Runner nicht erfolgreich. Logs:"
        kubectl -n "$NS" logs "job/${app}-restore-runner" --tail=40
        return 1
    fi

    # Step 5: App-Stack (OIDC-Secret falls vorhanden, dann HelmRelease)
    echo ""
    echo ">>> k8s: App-Stack ausrollen..."
    if [[ -f "${appdir}/oidc-secret.sops.yaml" ]]; then
        sops -d "${appdir}/oidc-secret.sops.yaml" | kubectl apply -f - || {
            echo "FEHLER: OIDC-Secret konnte nicht angewandt werden (SOPS/age?)"; return 1; }
    fi
    kubectl apply -f "${appdir}/values.yaml" -f "${appdir}/helmrelease.yaml" || return 1
    echo "    Warte auf App (kann beim ersten Mal dauern)..."
    kubectl -n "$NS" rollout status "deploy/${app_deploy}" --timeout=600s 2>/dev/null \
        || echo "    (App-Rollout noch nicht fertig - 'kubectl -n ${NS} get pods' pruefen)"

    # Browser-/resolver-unabhaengige Erreichbarkeit: /etc/hosts-Eintrag auf die
    # Traefik-LB-IP. Wird VOR jedem Resolver (auch Firefox-DoH-Fallback) gelesen.
    # Der Host existiert nur LAN-intern (k8s-gateway), daher kein oeffentliches DNS.
    local fqdn="${app}-restore.k8s.nexus4-2.de"
    local traefik_ip="192.168.1.240"
    echo ""
    echo ">>> /etc/hosts: ${fqdn} -> ${traefik_ip} (sudo)..."
    sudo sed -i '' "/[[:space:]]${fqdn}[[:space:]].*# restore_k8s$/d" /etc/hosts 2>/dev/null
    printf '%s %s # restore_k8s\n' "$traefik_ip" "$fqdn" | sudo tee -a /etc/hosts >/dev/null \
        && echo "    gesetzt" \
        || echo "    FEHLER: konnte /etc/hosts nicht schreiben (manuell: '${traefik_ip} ${fqdn}')"

    echo ""
    echo "========================================"
    echo "  Test-Restore '${app}' bereit"
    echo "========================================"
    echo "  URL:  https://${fqdn}"
    echo "  Pods: kubectl -n ${NS} get pods"
    echo "  Weg:  restore_k8s clean  (entfernt NS + /etc/hosts-Eintrag)"
}

# PROD-Restore: spielt ein Backup in die ECHTEN Ressourcen zurueck (DESTRUKTIV).
# Generische Orchestrierung; pro Service nur restore/<app>/prod/{profile.env,restore-runner-job.yaml}.
_restore_k8s_prod() {
    local app="$1"
    local archive="${2:-}"
    local REPO="${TALOS_REPO:-$HOME/repos/talos-k8s}"
    local NAS_SCRIPT="/mnt/backup/recovery/scripts/restore-push.sh"
    local NAS_HOST="k8s"
    local proddir="${REPO}/restore/${app}/prod"

    [[ -n "$app" ]] || { echo "FEHLER: App fehlt. Usage: restore_k8s --prod <app> [archive]"; return 1; }
    [[ -d "$proddir" ]] || { echo "FEHLER: kein Prod-Overlay unter ${proddir}"; return 1; }
    [[ -f "${proddir}/profile.env" ]] || { echo "FEHLER: profile.env fehlt in ${proddir}"; return 1; }
    [[ -f "${proddir}/restore-runner-job.yaml" ]] || { echo "FEHLER: restore-runner-job.yaml fehlt in ${proddir}"; return 1; }

    # Profil laden (Skalare fuer die generische Orchestrierung)
    local PROD_NAMESPACE APP_WORKLOAD APP_REPLICAS SNAPSHOT_PVCS
    source "${proddir}/profile.env"
    local ns="$PROD_NAMESPACE"
    local runner_job="${app}-prod-restore-runner"
    local inspect_job="${app}-prod-restore-inspect"
    local keyfile="${REPO}/restore/runner-ssh-key.sops.yaml"

    echo "============================================================"
    echo "  PROD-Restore '${app}' -> Namespace '${ns}'  (DESTRUKTIV)"
    echo "============================================================"

    # Step 1: NAS pusht die Restore-Daten (server-initiiert)
    echo ""
    echo ">>> [1/7] NAS: Restore-Daten extrahieren und pushen..."
    ssh nas "sudo -u recovery ${NAS_SCRIPT} ${NAS_HOST} ${app} ${archive}" || {
        echo "FEHLER: restore-push auf NAS fehlgeschlagen"; return 1; }

    # SSH-Key-Secret in den Prod-NS (SOPS-Namespace ueberschreiben: restore -> ${ns})
    echo ""
    echo ">>> [2/7] SSH-Key-Secret nach '${ns}'..."
    sops -d "$keyfile" | sed "s/^\( *\)namespace: restore$/\1namespace: ${ns}/" \
        | kubectl apply -f - || { echo "FEHLER: runner-ssh-key (SOPS/age?)"; return 1; }

    # Step 2: Dry-run / Diff - prueft v.a. dass das Backup NICHT leer ist (rsync --delete!)
    echo ""
    echo ">>> [3/7] Dry-run: Backup-Umfang pruefen..."
    kubectl -n "$ns" delete job "$inspect_job" --ignore-not-found >/dev/null 2>&1
    cat <<EOF | kubectl apply -f - >/dev/null || { echo "FEHLER: Inspect-Job"; return 1; }
apiVersion: batch/v1
kind: Job
metadata:
  name: ${inspect_job}
  namespace: ${ns}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: inspect
          image: postgres:18-alpine
          command: ["/bin/sh","-c"]
          args:
            - |
              set -eu
              apk add --no-cache rsync openssh-client >/dev/null
              mkdir -p ~/.ssh && chmod 700 ~/.ssh
              cp /ssh-key/id_ed25519 ~/.ssh/id_ed25519 && chmod 600 ~/.ssh/id_ed25519
              ssh-keyscan -p 22 backup-ssh.backup.svc.cluster.local > ~/.ssh/known_hosts 2>/dev/null
              REMOTE="backup@backup-ssh.backup.svc.cluster.local:/mnt/backup/restore/${app}"
              RSH="ssh -i ~/.ssh/id_ed25519"
              echo "--- Backup-Inhalt unter restore/${app}/ ---"
              rsync -n -a --stats -e "\$RSH" "\$REMOTE/" /tmp/probe/ 2>/dev/null \
                | grep -Ei "number of files|total file size" \
                || echo "WARN: rsync-Probe leer oder fehlgeschlagen"
          volumeMounts:
            - name: ssh-key
              mountPath: /ssh-key
              readOnly: true
      volumes:
        - name: ssh-key
          secret:
            secretName: restore-runner-ssh-key
            defaultMode: 0600
EOF
    kubectl -n "$ns" wait --for=condition=complete job/"$inspect_job" --timeout=300s >/dev/null 2>&1
    echo "------------------------------------------------------------"
    kubectl -n "$ns" logs job/"$inspect_job" 2>/dev/null | grep -vE "^(\+|set |apk )" || true
    kubectl -n "$ns" delete job "$inspect_job" --ignore-not-found >/dev/null 2>&1
    echo "------------------------------------------------------------"
    echo "  -> Wenn 'Total file size' 0/winzig ist: ABBRECHEN (rsync --delete wuerde Prod leeren)."

    # Step 3: Tipp-Bestaetigung
    echo ""
    echo "!!! Dieser Restore ist DESTRUKTIV:"
    echo "    - DB '${app}' wird gedroppt und neu erstellt"
    echo "    - Datei-PVCs werden gespiegelt (rsync --delete)"
    echo -n "Zum Fortfahren App-Namen exakt eintippen ('${app}'): "
    local confirm; read -r confirm
    [[ "$confirm" == "$app" ]] || { echo "Abgebrochen."; return 1; }

    # Step 4: Pre-Restore-VolumeSnapshots (Rollback-Punkt)
    echo ""
    echo ">>> [4/7] Pre-Restore-Snapshots anlegen..."
    local ts; ts=$(date +%Y%m%d-%H%M%S)
    local snapnames="" pvc snapname
    for pvc in ${=SNAPSHOT_PVCS}; do
        snapname="prerestore-${app}-${pvc}-${ts}"
        # k8s-Namen max 253 Zeichen; bei Bedarf kuerzen
        snapname="${snapname:0:253}"
        cat <<EOF | kubectl apply -f - >/dev/null || { echo "FEHLER: Snapshot ${pvc}"; return 1; }
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${snapname}
  namespace: ${ns}
  labels:
    restore.k8s/app: ${app}
spec:
  volumeSnapshotClassName: longhorn-snapshot
  source:
    persistentVolumeClaimName: ${pvc}
EOF
        echo "    + ${snapname}"
        snapnames="${snapnames} ${snapname}"
    done
    echo "    Warte auf readyToUse..."
    for snapname in ${=snapnames}; do
        kubectl -n "$ns" wait --for=jsonpath='{.status.readyToUse}'=true \
            volumesnapshot/"$snapname" --timeout=300s || {
            echo "FEHLER: Snapshot ${snapname} nicht ready - ABBRUCH (App noch oben)."; return 1; }
    done

    # Step 5: App herunterfahren (gibt RWO-PVCs frei; Postgres/Redis bleiben oben)
    echo ""
    echo ">>> [5/7] App herunterfahren (${APP_WORKLOAD} -> 0)..."
    kubectl -n "$ns" scale "$APP_WORKLOAD" --replicas=0 || return 1
    local tries=0 reps
    while :; do
        reps=$(kubectl -n "$ns" get "$APP_WORKLOAD" -o jsonpath='{.status.replicas}' 2>/dev/null)
        [[ -z "$reps" || "$reps" == "0" ]] && break
        tries=$((tries+1)); [[ $tries -gt 90 ]] && { echo "FEHLER: App nicht heruntergefahren"; return 1; }
        sleep 2
    done
    echo "    App-Pods weg."

    # Step 6: Runner (rsync-Pull + DB drop/recreate/load)
    echo ""
    echo ">>> [6/7] Restore-Runner (Dateien + DB)..."
    kubectl -n "$ns" delete job "$runner_job" --ignore-not-found >/dev/null 2>&1
    kubectl apply -f "${proddir}/restore-runner-job.yaml" || return 1
    if ! kubectl -n "$ns" wait --for=condition=complete job/"$runner_job" --timeout=1h; then
        echo "FEHLER: Restore-Runner nicht erfolgreich. Logs:"
        kubectl -n "$ns" logs job/"$runner_job" --tail=50
        echo ""
        echo "  App bleibt auf 0 Replicas (manueller Eingriff noetig)."
        echo "  Rollback ueber die Pre-Restore-Snapshots:${snapnames}"
        return 1
    fi

    # Step 7: App wieder hochfahren
    echo ""
    echo ">>> [7/7] App hochfahren (${APP_WORKLOAD} -> ${APP_REPLICAS})..."
    kubectl -n "$ns" scale "$APP_WORKLOAD" --replicas="$APP_REPLICAS" || return 1
    kubectl -n "$ns" rollout status "$APP_WORKLOAD" --timeout=600s \
        || echo "    (Rollout noch nicht fertig - 'kubectl -n ${ns} get pods' pruefen)"

    echo ""
    echo "============================================================"
    echo "  PROD-Restore '${app}' abgeschlossen"
    echo "============================================================"
    echo "  Pods:      kubectl -n ${ns} get pods"
    echo "  Snapshots: kubectl -n ${ns} get volumesnapshot -l restore.k8s/app=${app}"
    echo "  Rollback:  PVC aus Snapshot neu anlegen (spec.dataSource -> VolumeSnapshot)"
    echo "             bzw. Longhorn-Volume auf den Snapshot zuruecksetzen."
    echo "  Aufraeumen (Snapshots loeschen, wenn alles ok):"
    echo "             kubectl -n ${ns} delete volumesnapshot -l restore.k8s/app=${app}"
}
