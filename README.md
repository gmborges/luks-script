# luks-script
Script interativo para criptografia de volumes em sistemas Linux utilizando LUKS

FUNÇÕES:
1) Verificar qual é a partição criptografada
2) Verificar qual é o nome da partição mapeada
3) Adicionar uma chave de criptografia
4) Remover uma chave de criptografia
5) Realizar o backup do header do LUKS
6) Criptografar disco secundário

ARQUIVO luks-pass:
O arquivo 'luks-pass' possui a chave de criptografia.
Essa chave é utilizada na função 3 e na função 4.

MODO DE EXECUÇÃO:
1: Copie a pasta completa para o diretório /tmp (isso garantirá que os arquivos serão removidos ao desligar a máquina).
2: Em seguida, modifique a permissão do arquivo do script para torná-lo executável.
    chmod +x script_config_luks
3: Execute o script:
    ./script_config_luks
4: Escolha a opção 3 para configurar a chave de criptografia do usuário.
4.1: Caso a máquina possua uma disco secundário, execute a opção 6. É necessário que o segundo disco possua pelo menos uma partição.
5: Escolha a opção 5 para realizar o backup do header LUKS.
6: Garanta que o arquivo de backup esteja salvo no servidor desejado.
