#!/bin/bash

# init.sh - script de inicializacao do droplet
#
# o que faz:
#   - valida que eh ubuntu 24
#   - cria usuario ssh com sudo sem senha
#   - instala tailscale e conecta no tailnet
#
# acesso ao droplet:
#   - normal: tailscale ssh ${ssh_user}@nome-do-droplet
#   - emergencia: Recovery Console no painel da DigitalOcean
#
# por que Droplet Console nao funciona:
#   - cloud firewall bloqueia todo inbound (incluindo porta 22)
#   - Droplet Console usa SSH por baixo, entao nao conecta
#   - Recovery Console funciona porque eh acesso direto (tipo KVM)
#
# logs: cat /var/log/terraform-init.log

LOG="/var/log/terraform-init.log"
exec > >(tee -a $LOG) 2>&1

echo "==================== init: iniciando ===================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')]"

echo ""
echo "==================== validacao ubuntu versao ===================="
if ! grep -q "Ubuntu 24" /etc/os-release; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRO: verifique se o script init eh compativel com essa versao do ubuntu"
  exit 1
fi
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ubuntu 24 versao ok"

echo ""
echo "==================== usuario ssh ===================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] criando usuario ${ssh_user}"
useradd -m -s /bin/bash ${ssh_user}
usermod -aG sudo ${ssh_user}
echo "${ssh_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${ssh_user}
chmod 440 /etc/sudoers.d/${ssh_user}
echo "[$(date '+%Y-%m-%d %H:%M:%S')] usuario ${ssh_user} criado com sudo sem senha"

echo ""
echo "==================== tailscale ===================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] instalando tailscale"
curl -fsSL https://tailscale.com/install.sh | sh
echo "[$(date '+%Y-%m-%d %H:%M:%S')] conectando no tailnet"
tailscale up --auth-key=${ts_auth_key} --ssh
echo "[$(date '+%Y-%m-%d %H:%M:%S')] tailscale conectado"

echo ""
echo "==================== init: concluido ===================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')]"
