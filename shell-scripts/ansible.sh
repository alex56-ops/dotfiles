# Update services on server03 via Ansible
update() {
    if [[ "$1" == "-h" ]] || [[ -z "$1" ]]; then
        echo "Update services on server03 via Ansible"
        echo "Usage: update [--base|-b] <service1> [service2] ..."
        echo "  --base, -b  Include baseline and docker tags"
        echo "Example: update authelia immich"
        echo "         update -b authelia"
        [[ -z "$1" ]] && return 1 || return 0
    fi

    local skip_tags="--skip-tags baseline,docker"

    if [ "$1" = "--base" ] || [ "$1" = "-b" ]; then
        skip_tags=""
        shift
    fi

    local services="['$(echo "$@" | sed "s/ /','/g")']"

    ssh -t server03 \
        "cd /mnt/ansible/repo &&
         git pull &&
         ansible-playbook playbooks/services/main-updating.yml -e \"deploy_only=$services\" $skip_tags"
}

# Generate password and encrypt with Ansible Vault
encpass() {
  if [[ "$1" == "-h" ]]; then
      echo "Generate password and encrypt with Ansible Vault"
      echo "Usage: encpass [-x] <length> <name>"
      echo "  -x  Generate hex password instead of alphanumeric"
      echo "Example: encpass 32 my_secret"
      echo "         encpass -x 64 my_hex_token"
      return 0
  fi

  local use_hex=0
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -x) use_hex=1; shift ;;
      *)  args+=("$1"); shift ;;
    esac
  done

  if [ ${#args[@]} -ne 2 ]; then
    echo "Usage: encpass [-x] <length> <name>"
    return 1
  fi

  local length=${args[1]}
  local name=${args[2]}
  local password

  if [ $use_hex -eq 1 ]; then
    password=$(openssl rand -hex "$((length / 2))")
  else
    password=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | cut -c1-"$length")
  fi

  ansible-vault encrypt_string "$password" --name "$name"
}

# Decrypt an Ansible Vault encrypted string
decpass() {
  if [[ "$1" == "-h" ]]; then
      echo "Decrypt an Ansible Vault encrypted string"
      echo "Usage: decpass <encrypted_string>"
      return 0
  fi

  if [ $# -ne 1 ]; then
    echo "Usage: decpass <encrypted_string>"
    return 1
  fi

  echo "$1" | grep -v '!vault' | sed 's/^[[:space:]]*//' | ansible-vault decrypt --output -
  echo
}
