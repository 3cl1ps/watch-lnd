#!/bin/bash

# Reset
nc=$(tput sgr0)       # Text Reset
# Regular Colors
black=$(tput setaf 0)        # Black
red=$(tput setaf 1)          # Red
green=$(tput setaf 2)        # Green
yellow=$(tput setaf 3)      # Yellow
blue=$(tput setaf 4)         # Blue
purple=$(tput setaf 5)       # Purple
cyan=$(tput setaf 6)         # Cyan
white=$(tput setaf 7)        # White

PS1=$;PROMPT_COMMAND=;echo -en "\033]0;LND Watcher\a"
IFS=","
updatetime=$((60))
oldincome="0"
while : ;do
    #----------START--LND RPC POLLING----------------------------------------------
    height=`eval lncli getinfo |jq -r '.block_height'`
    walletbal=`eval lncli walletbalance |jq -r '.total_balance'`
    unconfirmed=`eval lncli walletbalance |jq -r '.unconfirmed_balance'`

    income=$(lncli feereport | jq .month_fee_sum | tr -d '"')

    fwding=`eval lncli fwdinghistory |jq -c '.forwarding_events[]|.amt_in+"("+.fee_msat+") "'|tr -d '\n"'`
    lncli fwdinghistory | jq -r '.forwarding_events[]|.chan_id_in,.chan_id_out' | sort > fwdlist.txt

    eval lncli listchannels > rawout.txt
    cat rawout.txt | jq -r '.channels[] |select(.private==false)| [.remote_pubkey,.local_balance,.remote_balance,(.active|tostring),(.initiator|tostring),.commit_fee,.chan_id,.total_satoshis_sent,.total_satoshis_received] | join("," )' > nodelist.txt
    reco=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==true) | "1"|tonumber]|add'`
    reci=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==false) | "1"|tonumber]|add'`
    unset_balanceo=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==true) |.unsettled_balance|tonumber]|add'`
    unset_balancei=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==false) | .unsettled_balance|tonumber]|add'`
    unset_times=`cat rawout.txt | jq -r -s '[.[].channels[].pending_htlcs[].expiration_height|select(length > 0)-'${height}'|tostring]|join(",")'`
    mybalance=`cat rawout.txt | jq -s '[.[].channels[].local_balance|tonumber]|add'`
    cap_balance=`cat rawout.txt | jq -s '[.[].channels[].remote_balance|tonumber]|add'`
    commitfees=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==true) | .commit_fee|tonumber]|add'`
    ocommitfees=`cat rawout.txt | jq -s '[.[].channels[]|select(.initiator==false) | .commit_fee|tonumber]|add'`
    outgoingcap=$(( ${mybalance} + ${commitfees} ))
    incomincap=$(( ${cap_balance} + ${ocommitfees} )) 

    eval lncli pendingchannels > rawoutp.txt
    cat rawoutp.txt | jq -r '.pending_open_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pendo","true",.commit_fee] | join("," )' >> nodelist.txt
    cat rawoutp.txt | jq -r '.waiting_close_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
    cat rawoutp.txt | jq -r '.pending_closing_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
    cat rawoutp.txt | jq -r '.pending_force_closing_channels[]|[.channel.remote_node_pub,.channel.local_balance,.channel.remote_balance,"pend c","true","0"] | join("," )' >> nodelist.txt
    limbo=`cat rawoutp.txt | jq -r '.total_limbo_balance'`
    limbot=`cat rawoutp.txt |grep _matur| cut -d":" -f2|tr -d "\n,"`

    #ME
    eval lncli getinfo | jq -r '[.identity_pubkey,"'${outgoingcap}'","'${incomincap}'","--me--","x "," "]| join("," )' >> nodelist.txt  #add own node to list
    my_pubid=`eval lncli getinfo | jq -r .identity_pubkey`

    sort nodelist.txt -o nodelist.txt
    myrecs=$(wc -l nodelist.txt | sed -e 's/ .*//')
    updatetimed=$updatetime
    walletbal="             ${walletbal}";walletbalA="${walletbal:(-9):3}";walletbalB="${walletbal:(-6):3}";walletbalC="${walletbal:(-3):3}";walletbal="${walletbalA// /} ${walletbalB// /} ${walletbalC// /}";walletbal="${walletbal/  /}"
    #----------START--TABLE BUILDER------------------------------------------------
    rm -f combined.txt     #just in case of program interruption
    while read -r thisID balance incoming cstate init cf chanid total_sat_sent total_sat_recv; do
        #--------------processing
        title=`eval lncli getnodeinfo ${thisID} |jq -r '.node.alias'| tr -d "<')(>&|," |tr -d '"´'|tr -dc [:print:][:cntrl:]`    #remove problem characters from alias
        ipexam=`eval lncli getnodeinfo ${thisID} |jq -r '.node.addresses[].addr'`	
        ipstatus="-ip4-";ipcolor="089m"
        if [[ $ipexam == *"n:"* ]];then        ipstatus="onion";ipcolor="113m";fi
        if [[ $ipexam == *":"*":"* ]];then     ipstatus="mixed";ipcolor="111m";fi
        if [[ $ipexam == *"n:"*"n:"* ]];then   ipstatus="onion";ipcolor="113m";fi
        if [[ $ipexam == *":"*":"*":"* ]];then ipstatus="mixed";ipcolor="111m";fi
        if [[ "$total_sat_recv" = "" ]]; then total_sat_recv=0; fi;
        if [[ "$total_sat_sent" = "" ]]; then total_sat_sent=0; fi;
        total_sat_recv=`echo ${total_sat_recv} / 100000000| bc -l`
        total_sat_sent=`echo ${total_sat_sent} / 100000000| bc -l`
        total_sat_recv=${total_sat_recv:0:4}
        total_sat_sent=${total_sat_sent:0:4}
        if [[ $total_sat_sent < 0.01 ]]; then total_sat_sent=$(echo "$red$total_sat_sent$nc");fi
        if [[ $total_sat_recv < 0.01 ]]; then total_sat_recv=$(echo "$red$total_sat_recv$nc");fi
        
        thiscapacity=`eval lncli getnodeinfo $thisID | jq -r .total_capacity`
        subthiscapacity=`echo $thiscapacity / 100000000 | bc -l`
        thisconnectedcount=`eval lncli getnodeinfo $thisID | jq -r .num_channels`
        subavgchancap=`echo $thiscapacity / $thisconnectedcount / 100000000| bc -l`
        avgchancap=`echo $subavgchancap | sed 's/^\./0./'`
        avgchancap=${avgchancap:0:6}
        if [[ $avgchancap < 0.03 ]]; then avgchancap=$(echo "$red$avgchancap$nc");fi
        if [ ! $chanid = "" ]; then
            test_id=`eval lncli getchaninfo $chanid | jq -r .node1_pub`
            fees=""
            if [ "$my_pubid" = "$test_id" ]; then
                fees=`lncli getchaninfo $chanid | jq -r '.node2_policy | .fee_rate_milli_msat'`
            else
                fees=`lncli getchaninfo $chanid | jq -r '.node1_policy | .fee_rate_milli_msat'`
            fi
        fi
        if [ $fees -gt 999 ]; then fees=$(echo $red$fees$nc);fi
        if [ "${cstate:0:1}" = "f" ];then 
            cstate=$(echo "$(( ( $(date +%s) - $(lncli getnodeinfo ${thisID} |jq -r '.node.last_update') ) / 3600 ))'\e[38;5;089m'hrs'\e[0m'" )
            if [[ "${cstate:0:1}" -lt "2" && "${cstate:1:1}" == "'" ]];then 
                cstate=$(echo "$(( ( $(date +%s) - $(lncli getnodeinfo ${thisID} |jq -r '.node.last_update') ) /   60 ))'\e[38;5;113m'min'\e[0m'" )
            fi
        elif [ "${cstate}" = "pend c" ];then 
            cstate=$(echo "'\e[38;5;007m'$cstate'\e[0m'" )
        else 
            cstate=$(echo "'\e[38;5;232m\e[0m'$cstate" )
        fi
        if [ "${chanid:0:1}" = "6" ];then 
            fwdcount=`eval cat fwdlist.txt | grep -c -s $chanid`
            if [ "$fwdcount" -gt "0" ];then     cstate=$(echo "$cstate$fwdcount" ); fi
        fi   
        if   [ "$init"   = "true" ];then 
            balance=$(( $balance + $cf ))
        elif [ "$init"   = "false" ];then 
            incoming=$(( $incoming + $cf ))
        fi
        #colonne equilibre 
        equilibre=`echo $balance / $incoming | bc -l`
        equilibre=${equilibre:0:4}
        if (( $(echo "$equilibre > 60" |bc -l) )); then
            equilibre=$red$equilibre$nc
        elif (( $(echo "$equilibre < 0.8" |bc -l) )); then
            equilibre=$yellow$equilibre$nc
        fi
        if [ "$balance"   = "0" ];then balance="";fi
        if [ "$incoming"  = "0" ];then incoming="";fi
        if [[ -n "$incoming" ]];then 
            incoming="          ${incoming}"
            incomingA="${incoming:(-9):3}"
            incomingB="${incoming:(-6):3}"
            incomingC="${incoming:(-3):3}"
            incoming="${incomingA// /} ${incomingB// /} ${incomingC// /}"
            incoming="${incoming/  /}"
        fi
        if [[ -n "$balance" ]];then 
            abalance="           ${balance}"
            balanceA="${abalance:(-9):3}"
            balanceB="${abalance:(-6):3}"
            balanceC="${abalance:(-3):3}"
            balance="${balanceA// /} ${balanceB// /} ${balanceC// /}"
            balance="${balance/  /}"
        fi

        incoming="'\e[38;5;232m'_____________'\e[0m'${incoming}";incoming="${incoming:0:14}${incoming: -19}"
        balance="'\e[38;5;232m'_____________'\e[0m'${balance}";balance="${balance:0:14}${balance: -19}"
        #--------------display table size configurator
        OUTPUTME=`eval echo "${chanid:0:2}${chanid:2},$balance,$incoming,"$title",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate},$init,$thisconnectedcount,${subthiscapacity:0:6},${avgchancap},$fees,${total_sat_recv},${total_sat_sent},${equilibre}"`
        header="[38;5;232m02[0m Channel   ID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mType,[38;5;001m[0mActive,Init,Channels,Capac.,AvgChan,Fees (m msat),RECV,SENT,Equili"
        echo "${OUTPUTME}" >> combined.txt
    done <nodelist.txt 
    #----------START--DISPLAY & WAIT---------------------------------------------
    bosScore=$(curl https://nodes.lightning.computer/availability/v1/btc.json | jq '.scores[] | select(.alias == "eclips.lnd") | .score') 
    loop=`eval pgrep -x loopd >/dev/null && echo $green"OK"$nc || echo $red"KO"$nc`
    pool=`eval pgrep -x poold >/dev/null && echo $green"OK"$nc || echo $red"KO"$nc`
    echo -e "${header}\n`cat combined.txt|sort -d -i --field-separator=',' -k 7r,7r -k 6,6 -k 3 `"  | column -n -ts, > myout.txt  #main data table
    clear;  echo -e `cat myout.txt` #helps with screen refresh lag?  
    echo -e "  (${unconfirmed} unconf) (${limbo} in limbo$limbot) (${unset_balanceo} / ${unset_balancei} unsettled ${unset_times}) Recent fwds: ${fwding}"
    echo -e "In wallet: \e[38;5;45m${walletbal}\e[0m    Income (month) : \e[38;5;83m${income}\e[0m sat   Channels: \e[38;5;99m$(( $myrecs - 1))\e[0m (${reco}/${reci})   BOS score: $yellow$bosScore$nc   LOOP : $loop   POOL : $pool"

    rm -f combined.txt myout.txt nodelist.txt rawout.txt rawoutp.txt fwdlist.txt

    secsi=$updatetimed;
    while [ $secsi -gt -1 ]; do 
        for (( c=1; c<=$(( $updatetimed - $secsi )); c++ )); do 
            echo -ne " ";
        done ;  
        for (( c=1; c<=$(( $secsi )); c++ )); do 
            echo -ne "»";done ;echo -ne " \e[38;5;173m$secsi\e[0m "
            for (( c=1; c<=$(( $secsi )); c++ )); do 
                echo -ne "«";
            done
            echo -en "\033[0K\r\e[?25l"; 
            if  [ $secsi -ne 0 ]; then 
                sleep 1;
            fi  
            : $((secsi--));
        done   #countdown
    done
