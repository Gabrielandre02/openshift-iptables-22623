#!/usr/bin/env bash

# Definição da imagem usada para depuração no OpenShift
OCDEBUGIMAGE="quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:40c7eac9c5d21bb9dab4ef3bffa447c48184d28b74525e118147e29f96d32d8e"

# Número de execuções paralelas permitidas
PARALLELJOBS=5

# Arquivo temporário para registrar erros
ERRORFILE="/tmp/errorfile"

# Códigos de status para diferentes tipos de resultados
OCERROR=1      # Erro
OCOK=0         # Sucesso
OCSKIP=2       # Permissão insuficiente
OCUNKNOWN=3    # Estado desconhecido

# Criação de um arquivo temporário para armazenar erros
tmperrorfile=$(mktemp)
trap "rm -f ${tmperrorfile}" EXIT  # Remove o arquivo temporário ao sair do script
echo 0 > "$tmperrorfile"

# Verifica se o usuário tem permissão para depurar nós no OpenShift
if ! oc auth can-i debug nodes >/dev/null 2>&1; then
  printf "Sem permissão para depurar nós. Verifique suas permissões.\n" >&2
  exit ${OCSKIP}
fi

printf "Verificando e removendo regras do firewall nos nós...\n"

# Obtém a lista de nós no cluster
NODES=$(oc get nodes --no-headers -o custom-columns=":metadata.name")

# Itera sobre cada nó para verificar e remover regras de firewall
for node in ${NODES}; do
  ((i = i % PARALLELJOBS))  # Controla a execução paralela
  ((i++ == 0)) && wait
  (
    printf "Acessando nó: %s\n" "$node"

    # Executa um comando de depuração no nó e executa um script dentro do contêiner
    OUTPUT=$(oc debug node/"${node}" -- bash -c '
      chroot /host /bin/bash -c "
        printf \"Verificando e removendo regras do firewall...\n\"

        # Função para remover regras do iptables
        remove_iptables_rules() {
          local CHAIN=\$1
          local PORT=\$2

          while true; do
            RULE_NUMS=\$(iptables -L \"\$CHAIN\" -n --line-numbers | grep \"dpt:\$PORT\" | awk \"{print \\\$1}\" | tac)

            [[ -z \"\$RULE_NUMS\" ]] && break

            for RULE_NUM in \$RULE_NUMS; do
              printf \"Removendo regra %s número %s para porta %s...\n\" \"\$CHAIN\" \"\$RULE_NUM\" \"\$PORT\"
              iptables -D \"\$CHAIN\" \"\$RULE_NUM\"
            done
          done
        }

        # Função para remover regras do nftables
        remove_nft_rules() {
          local TABLE=\"filter\"
          local CHAIN=\$1
          local PORT=\$2

          RULE_HANDLES=\$(nft list ruleset | grep \"dport \$PORT\" | awk \"{print \\\$NF}\")

          for HANDLE in \$RULE_HANDLES; do
            printf \"Removendo regra da cadeia %s para porta %s (handle %s)...\n\" \"\$CHAIN\" \"\$PORT\" \"\$HANDLE\"
            nft delete rule ip \"\$TABLE\" \"\$CHAIN\" handle \"\$HANDLE\"
          done
        }

        # Verifica se o iptables está disponível e executa a remoção
        if command -v iptables &>/dev/null && iptables -L &>/dev/null; then
          printf \"Usando iptables...\n\"
          remove_iptables_rules FORWARD 22623
          remove_iptables_rules FORWARD 22624
          remove_iptables_rules OUTPUT 22623
          remove_iptables_rules OUTPUT 22624
        # Caso contrário, verifica se o nftables está disponível
        elif command -v nft &>/dev/null && nft list ruleset &>/dev/null; then
          printf \"Usando nftables...\n\"
          remove_nft_rules FORWARD 22623
          remove_nft_rules FORWARD 22624
          remove_nft_rules OUTPUT 22623
          remove_nft_rules OUTPUT 22624
        else
          printf \"Nenhum firewall compatível encontrado. Verifique manualmente.\n\" >&2
          exit 1
        fi
      "
    ' 2>&1)

    # Registra o log da execução
    printf "LOG DO NÓ %s:\n%s\n" "$node" "$OUTPUT" >> /tmp/debug_output.log

    # Verifica se as regras foram removidas ou se houve erro
    if [[ ${OUTPUT} =~ "Removendo regra" ]]; then
      printf "Regras removidas no nó %s.\n" "$node"
    elif [[ ${OUTPUT} =~ "Nenhum firewall compatível encontrado" ]]; then
      printf "Erro no nó %s: firewall não suportado.\n" "$node" >&2
      echo 1 > "$tmperrorfile"
    else
      printf "Erro desconhecido no nó %s. Verifique /tmp/debug_output.log\n" "$node" >&2
      echo 1 > "$tmperrorfile"
    fi
  ) &
done

wait

# Exibe o resultado final do script
if [[ "$(cat "$tmperrorfile")" -eq 1 ]]; then
  printf "Erros foram encontrados em alguns nós. Verifique os logs em /tmp/debug_output.log\n" >&2
  exit ${OCERROR}
else
  printf "Processo concluído com sucesso. Nenhuma regra bloqueando as portas 22623/tcp e 22624/tcp foi encontrada ou todas foram removidas.\n"
  exit ${OCOK}
fi
