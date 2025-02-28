# Script de Remoção de Regras do Firewall em Nós OpenShift

## Descrição
Este script verifica e remove regras de firewall que podem estar bloqueando as portas **22623** e **22624** nos nós de um cluster OpenShift.

## Pré-requisitos
- Acesso ao cluster OpenShift com permissões para depurar nós (`oc auth can-i debug nodes`).
- Ferramentas `iptables` ou `nftables` disponíveis no ambiente.
- `oc` CLI instalado e configurado.

## Como Executar
1. Faça o download do script e conceda permissão de execução:
```bash
chmod +x iptables-openshift-22623.sh
```

## Execute o script:
```bash
./iptables-openshift-22623.sh
```

## Logs e Depuração
Os logs de execução são armazenados em /tmp/debug_output.log.
Caso ocorra um erro, o script sairá com código 1 e informará os nós afetados.

## Código de Saída
```bash
0: Execução bem-sucedida.
1: Erros foram encontrados.
2: Permissões insuficientes.
```