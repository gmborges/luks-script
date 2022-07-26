#!/bin/bash
# PURPOSE:  Script utilizado para configuração de chave de criptografia no LUKS
# AUTHOR:   Gabriel Borges
# DATE:     19/09/2021

YELLOW="\e[0;33m"
GREEN="\e[0;32m"
RED="\e[0;31m"
NC="\e[0m"

function valida_root (){
    #Verifica se o script foi executado com o usuário root
    if [[ $USER != "root" ]]; then
        echo ""
        echo "O script deve ser executado como root!"
        echo "Execute o comando 'sudo su -' e tente novamente."
        echo ""
        exit 1
    fi
}

function verifica_cryptsetup (){
    echo -e "\nVerificando se o pacote 'cryptsetup' está instalado..."
    sleep 1
    dpkg -s cryptsetup > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "[ OK ] cryptsetup instalado"
        echo ""
    else
        echo "[ FAIL ] cryptsetup não está instalado"
        exit 1
    fi
}

function verifica_cifs-utils (){
    echo -e "\nVerificando se o pacote 'cifs-utils' está instalado..."
    sleep 1
    dpkg -s cifs-utils > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "[ OK ] cifs-utils instalado"
    else
        echo "[ PENDING ] cifs-utils não está instalado"
        echo -e "\nInstalando cifs-utils..."
        apt install cifs-utils -y &> /dev/null
    fi
}

function verifica_partition_crypted (){
    echo -e "\nVerificando qual é a partição criptografada..."
    for dir in $(ls -1 /dev)
    do
        PARTITION="/dev/$dir"
        PARTCRYPT_D=""
        cryptsetup isLuks $PARTITION &> /dev/null
        if [[ $? -eq 0 ]]; then
            PARTCRYPT="$dir"
            PARTCRYPT_D="/dev/$dir"
            echo "[ OK ] Partição criptografada identificada: $PARTCRYPT_D"
            break
        fi
    done
    if [[ -z $PARTCRYPT_D ]]; then
        echo "[ FAIL ] Nenhuma partição criptografada identificada"
        exit 1
    fi
}

function verifica_partition_mapped (){
    echo -e "\nVerificando qual é a partição mapeada..."
    sleep 1

    PARTMAPPED=`ls -1 /dev/mapper/*_crypt 2> /dev/null | cut -d "/" -f 4`
    if [[ -z $PARTMAPPED ]]; then
        echo "[ FAIL ] Não há partição mapeada :(";
        exit 1
    else
        echo "[ OK ] Partição identificada: $PARTMAPPED";
    fi
}

function configura_luks_key (){
    echo -e "\nConfigurando senha do usuário ao LUKS..."
    read -s -p "Digita a senha de criptografia: " USERPASS
    printf "$USERPASS" > /tmp/luks-pass-user
    sleep 1
    cryptsetup luksAddKey $PARTCRYPT_D /tmp/luks-pass-user <<< `cat luks-pass`

    if [[ $? -ne 0 ]]; then
        echo ""
        echo "[ FAIL ] Aconteceu um erro durante a configuração da chave!"
        exit 1
    else
        echo ""
        echo "[ OK ] Chave configurada com sucesso! É aconselhado realizar um novo backup do Header LUKS"
    fi
}

function remove_luks_key (){
    echo -e "\nRemovendo senha do LUKS..."
    read -s -p "Digita a senha de criptografia: " REMOVEPASS
    printf "$REMOVEPASS" > /tmp/luks-pass-remove
    sleep 1
    cryptsetup luksRemoveKey $PARTCRYPT_D /tmp/luks-pass-remove <<< `cat luks-pass`

    if [[ $? -ne 0 ]]; then
        echo ""
        echo "[ FAIL ] Aconteceu um erro durante a remoção da chave!"
        exit 1
    else
        echo ""
        echo "[ OK ] Chave removida com sucesso!"
    fi

}

function realiza_backup_header (){
    echo -e "\nRealizando backup do Header do LUKS para a possível necessidade de recuperação..."
    HEADERFILE="/tmp/`hostname`-LuksHeader.bin"

    test -f $HEADERFILE && rm $HEADERFILE
    
    cryptsetup luksHeaderBackup $PARTCRYPT_D --header-backup-file $HEADERFILE

    if [[ $? -ne 0 ]]; then
        echo -e "[ FAIL ] Aconteceu um erro durante o backup do Header LUKS!\n"
    else
        echo -e "[ OK ] Backup realizado com sucesso em /tmp/`hostname`-LuksHeader.bin!\n"

        echo "Montando pasta compartilhada do servidor de arquivos para salvar o backup do Header LUKS..."
        echo "Antes de prosseguir:"
        echo "1º - Verifique se a conexão com o servidor está funcionando"
        echo "2º - Atenção para digitar o usuário e a senha corretamente"
        echo ""

        read -p "Digite o hostname do servidor de arquivos: " FILESERVER
        read -p "Digite o domínio: " SMBDOMAIN
        read -p "Digite o usuário: " SMBUSER
        read -s -p "Digite a senha: " SMBPASS

        echo ""
        verifica_cifs-utils

        test -d "/mnt/$FILESERVER" || mkdir /mnt/$FILESERVER
        mount | grep "/mnt/$FILESERVER" &> /dev/null

        if [[ $? -eq 0 ]]; then
            echo -e "\n[ OK ] O diretório já estava montado\n"
            echo "Copiando arquivo para o servidor..."

            if [[ -f "/mnt/$FILESERVER/luks_header_criptografia/`hostname`-LuksHeader.bin" ]]; then
                rm "/mnt/$FILESERVER/luks_header_criptografia/`hostname`-LuksHeader.bin"
            fi

            cp $HEADERFILE /mnt/$FILESERVER/luks_header_criptografia && echo "[ OK ] Concluído!" || "[ FAIL ] Houve um problema durante a cópia, realize-a manualmente"

        else
            mount -t cifs -o username=$SMBUSER,password=$SMBPASS,domain=$SMBDOMAIN //$FILESERVER/Arquivos /mnt/$FILESERVER &> /dev/null

            if [[ $? -ne 0 ]]; then
                echo -e "\n[ FAIL ] Não foi possível montar a pasta do servidor $FILESERVER.\n
                Devido a conexão ter falhado, salve manualmente o arquivo de backup do header no servidor.\n"

            else
            
                echo -e "\n[ OK ] Montagem realizada com sucesso!\n"
                echo "Copiando arquivo para o servidor..."

                if [[ -f "/mnt/$FILESERVER/luks_header_criptografia/`hostname`-LuksHeader.bin" ]]; then
                    rm "/mnt/$FILESERVER/luks_header_criptografia/`hostname`-LuksHeader.bin"
                fi

                cp $HEADERFILE /mnt/$FILESERVER/luks_header_criptografia && echo "[ OK ] Concluído!" || "[ FAIL ] Houve um problema durante a cópia, realize-a manualmente"
            fi

        fi
    fi
}

function verifica_disk_not_crypted (){
    DISKS=()

    clear
    echo -e "\nVerificando criptografia em discos..."
    sleep 1

    for dir in $(lsblk -l | grep disk | cut -f1 -d " ")
    do
        DISK="/dev/$dir"
        if [[ $PARTCRYPT_D =~ .*$DISK.* ]]; then
            printf "${GREEN}[$DISK]${NC} Disco criptografado\n";
        else
            printf "${RED}[$DISK]${NC} Disco NÃO criptografado\n";
            DISKS+=($dir)
        fi
    done

    if [[ ${#DISKS[@]} -ne 0 ]]; then
        CHOSENDISK=""
        while [[ -z $CHOSENDISK || $CHOSENDISK -gt ${#DISKS[@]} ]]
        do
            echo -e "\nQual disco você deseja criptografar?"
            # Lista os discos dentro do Array DISKS
            for index in `seq ${#DISKS[@]}`
            do
                echo "$index - ${DISKS[`expr $index-1`]}"
            done
            read CHOSENDISK
            DISKTOBECRYPT=${DISKS[`expr $CHOSENDISK-1`]}
        done
    else
        echo "Não há discos a serem criptografados!"
        exit 5
    fi
}

function escolhe_particao_para_criptografar (){
    PARTS=()
    CHOSENPART=""

    clear
    echo -e "\nVerificando criptografia nas partições do disco $DISKTOBECRYPT..."
    sleep 1

    # Grava as partições do disco em array
    for parts in $(lsblk -r | grep $DISKTOBECRYPT | grep part | cut -d " " -f 1)
    do
        PARTS+=($parts)
    done

    while [[ -z $CHOSENPART || $CHOSENPART -gt ${#DISKS[@]} ]]
    do
        echo -e "\nQual partição você deseja criptografar?"
        for index2 in ${#PARTS[@]}
        do
            echo "$index2 - ${PARTS[`expr $index2-1`]}"
        done
        read CHOSENPART
        PARTTOBECRYPT=${PARTS[`expr $CHOSENPART-1`]}
    done
}

function criptografia_disco_secundario (){
    clear
    echo -e "\nCriando chave de criptografia randômica..." ; sleep 1
    dd if=/dev/urandom of=/root/chave bs=4096 count=1 &> /dev/null

    echo -e "\nAjustando permissão do arquivo da chave randômica..." ; sleep 1
    chmod 400 /root/chave

    echo -e "\nFormatando partição /dev/$PARTTOBECRYPT com LUKS..." ; sleep 1
    cryptsetup -v luksFormat /dev/$PARTTOBECRYPT <<< $(cat luks-pass)

    echo -e "\nRealizando a abertura da partição criptografada..." ; sleep 1
    cryptsetup luksOpen /dev/$PARTTOBECRYPT "$PARTTOBECRYPT"_crypt <<< $(cat luks-pass)

    echo -e "\nDefinindo o tipo de sistema de arquivos (ext4) à partição..." ; sleep 1
    mkfs.ext4 /dev/mapper/"$PARTTOBECRYPT"_crypt

    echo -e "\nAdicionando chave de criptografia randômica ao disco criptografado..." ; sleep 1
    cryptsetup luksAddKey /dev/$PARTTOBECRYPT /root/chave <<< $(cat luks-pass)

    echo -e "\nConfigurando arquivo de configuração crypttab..." ; sleep 1
    grep "$PARTTOBECRYPT" /etc/crypttab > /dev/null
    if [ $? -eq 1 ]; then
        echo ""$PARTTOBECRYPT"_crypt    /dev/$PARTTOBECRYPT /root/chave luks" >> /etc/crypttab
    else
        echo -e "\nJá há uma entrada pertinente a esse disco no arquivo crypttab. Revise o conteúdo desse arquivo."
    fi

    echo -e "\nConfigurando arquivo de configuração fstab..." ; sleep 1
    grep "/dev/mapper/"$PARTTOBECRYPT"_crypt" /etc/fstab > /dev/null
    if [ $? -eq 1 ]; then

        echo "Adicionando pasta /arquivos e atribuindo permissões ao usuário final..."
        read -p "Informe o usuario final da máquina:" ENDUSER
        mkdir /arquivos && chown $ENDUSER:$ENDUSER /arquivos && chmod 750 /arquivos

        echo -e "\nConfigurando arquivo de configuração crypttab..."
        echo "/dev/mapper/"$PARTTOBECRYPT"_crypt    /arquivos   ext4    defaults    0   0" >> /etc/fstab

        echo -e "\nConcluído! Reinicie a máquina e verifique se a partição criptografada foi mapeada automaticamente ao diretório /arquivos"
    
    else
        echo "Já há uma entrada pertinente a esse disco no arquivo fstab. Revise o conteúdo desse arquivo."
    fi
}

function menu (){
    OPCAO=""

    while [[ -z $OPCAO || $OPCAO -gt 6 ]];
    do
        echo "======================="
        echo "Automação LUKS encryption"
        echo "======================="
        echo "Escolha uma das opções abaixo:"
        echo "1 - Verificar partição criptografada"
        echo "2 - Verificar o nome da partição mapeada"
        echo "3 - Configurar chave de criptografia"
        echo "4 - Remover uma chave de criptografia"
        echo "5 - Realizar backup do header do LUKS"
        echo "6 - Criptografar disco secundário"
        echo "7 - Sair"
        echo ""
        
        read OPCAO

        case $OPCAO in
        
            1 )
                verifica_partition_crypted
            ;;
            2 )
                verifica_partition_mapped
            ;;
            3 )
                verifica_partition_crypted
                configura_luks_key
            ;;
            4 )
                verifica_partition_crypted
                remove_luks_key
            ;;
            5 )
                verifica_partition_crypted
                realiza_backup_header
            ;;
            6 )
                verifica_partition_crypted
                verifica_disk_not_crypted
                if [[ $? -ne 5 ]]; then
                    escolhe_particao_para_criptografar
                    criptografia_disco_secundario
                fi
            ;;
            7 )
                exit
            ;;
            *)
                echo -e "Opção inválida \n"
                sleep 1
                clear
                continue
            ;;
        esac
    done
}

function main (){
    valida_root
    verifica_cryptsetup
    menu
}

main