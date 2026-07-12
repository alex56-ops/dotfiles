# DNS-Records der hb-studios.de-Zone bei INWX verwalten (Account hbstudios)
hb-inwx-dns() {
    if [[ "$1" == "-h" || -z "$1" ]]; then
        echo "DNS-Records der hb-studios.de-Zone bei INWX verwalten (Account hbstudios)"
        echo "Zugangsdaten kommen aus dem Cluster-Secret inwx-credentials-hbstudios; 2FA via TOTP"
        echo "Usage: hb-inwx-dns list"
        echo "       hb-inwx-dns add <name> <ziel> [typ] [ttl]   (Default: CNAME, 3600)"
        echo "       hb-inwx-dns del <name> [typ]"
        echo "Example: hb-inwx-dns add abc123-demo bonn-home.duckdns.org"
        return 0
    fi

    if ! command -v kubectl &>/dev/null; then
        echo "Fehler: kubectl ist nicht installiert (liefert die INWX-Zugangsdaten)"
        return 1
    fi

    python3 "$HOME/.shell-scripts/python-scripts/hb_inwx_dns.py" "$@"
}
