#!/bin/bash
#calc(){ awk "BEGIN { print "$*" }"; }

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
    cat rawout.txt | jq -r '.channels[] |select(.private==false)| [.remote_pubkey,.local_balance,.remote_balance,(.active|tostring),(.initiator|tostring),.commit_fee,.chan_id] | join("," )' > nodelist.txt
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

    eval lncli getinfo | jq -r '[.identity_pubkey,"'${outgoingcap}'","'${incomincap}'","--me--","x "," "]| join("," )' >> nodelist.txt  #add own node to list
    my_pubid=`eval lncli getinfo | jq -r .identity_pubkey`

    sort nodelist.txt -o nodelist.txt
    colorda="007m";colordb="007m";colordc="007m";colordd="007m";colorde="001m";updatetimed=$updatetime
    walletbal="             ${walletbal}";walletbalA="${walletbal:(-9):3}";walletbalB="${walletbal:(-6):3}";walletbalC="${walletbal:(-3):3}";walletbal="${walletbalA// /} ${walletbalB// /} ${walletbalC// /}";walletbal="${walletbal/  /}"
    #----------START--WEB DATA GRABBER---------------------------------------------
    myrecs=$(wc -l nodelist.txt | sed -e 's/ .*//')
    savedrecs=$(wc -l pages/webdata.txt | sed -e 's/ .*//')
    dirty=false
    while read thisID unused; do
        #1440min = 24h
        if ! test -f "pages/$thisID.html" || test "`find pages/$thisID.html -mmin +8440`" || ! test -f "pages/webdata.txt" ;then dirty=true;break    #freshness check
        elif [ "$myrecs" != "$savedrecs" ];then dirty=true;break;fi
    done < nodelist.txt
    if [ "$dirty" = true ];then
        mkdir -p pages;rm -f pages/webdata.txt
        echo "Downloading data about $myrecs nodes from 1ml.com : "`date`
        barlen=$(( $displaywidth )) 
        for (( c=1; c<=$(( $barlen - ( $(( $barlen  / $myrecs )) * $myrecs ) )); c++ )); do echo -ne "=";done        #fill in gap bars segments
        while read thisID f2 f3 f4 f5; do
            if ! test -f "pages/$thisID.html" || test "`find pages/$thisID.html -mmin +8440`";then  #freshness check
                eval curl -s https://1ml.com/node/$thisID -o pages/$thisID.html   #download html
                for (( c=1; c<=$(( $barlen  / $myrecs / 2 )); c++ )); do echo -n -e "\e[38;5;54m=\e[0m";done    #draw bar segment
            else for (( c=1; c<=$(( $barlen  / $myrecs / 2 )); c++ )); do echo -n -e "\e[38;5;235m=\e[0m";done;fi   #draw bar segment
            hex=`eval head -n 200 pages/$thisID.html| grep -A1 '<h5>Color</h5>' | pup span text{} | jq -r -R '.[1:7]'`
            r=$(printf '0x%0.2s' "$hex"); g=$(printf '0x%0.2s' ${hex#??}); b=$(printf '0x%0.2s' ${hex#????})  #hex to ansi color conversion
            thiscolor=$(echo -e `printf "%03d" "$(((r<75?0:(r-35)/40)*6*6+(g<75?0:(g-35)/40)*6+(b<75?0:(b-35)/40)+16))"`)"m"
            thiscapacity=`eval lncli getnodeinfo $thisID | jq -r .total_capacity`
            thisconnectedcount=`eval lncli getnodeinfo $thisID | jq -r .num_channels`
            
            avgchancap=`echo $thiscapacity / $thisconnectedcount | bc -l`
            thisbiggestchan=`eval cat pages/$thisID.html| grep -A1 '<h5 class="inline">Capacity</h5>'| pup span text{} | jq -r -R '.[0:-4]' | jq -s max`

            title=`eval lncli getnodeinfo ${thisID} |jq -r '.node.alias'| tr -d "<')(>&|," |tr -d '"´'|tr -dc [:print:][:cntrl:]`    #remove problem characters from alias
            ipexam=`eval lncli getnodeinfo ${thisID} |jq -r '.node.addresses[].addr'`	
            ipstatus="-ip4-";ipcolor="089m"
            if [[ $ipexam == *"n:"* ]];then        ipstatus="onion";ipcolor="113m";fi
            if [[ $ipexam == *":"*":"* ]];then     ipstatus="mixed";ipcolor="111m";fi
            if [[ $ipexam == *"n:"*"n:"* ]];then   ipstatus="onion";ipcolor="113m";fi
            if [[ $ipexam == *":"*":"*":"* ]];then ipstatus="mixed";ipcolor="111m";fi
            for (( c=1; c<=$(( ( $barlen  / $myrecs ) - $(( $barlen  / $myrecs / 2 )) )); c++ )); do echo -ne "\e[38;5;99m=\e[0m";done     #draw bar segment
            subthiscapacity=`echo $thiscapacity / 100000000 | bc -l`
            subavgchancap=`echo $avgchancap / 100000000 | bc -l`
            eval echo "${thisID},${title},${ipstatus},${ipcolor},${subthiscapacity},${thisconnectedcount},${subavgchancap},${thisbiggestchan},${thiscolor}" >> pages/webdata.txt  #write line to file
        done < nodelist.txt
    fi
    #----------START--TABLE BUILDER------------------------------------------------
    rm -f combined.txt     #just in case of program interruption
    while read -r thisID balance incoming cstate init cf chanid && read -r thatID title ipstatus ipcolor thiscapacity thisconnectedcount avgchancap thisbiggestchan color junk <&3; do
        #--------------processing
        if [ ! $chanid = "" ]; then
            test_id=`eval lncli getchaninfo $chanid | jq -r .node1_pub`
            fees=""
            if [ "$my_pubid" = "$test_id" ]; then
                fees=`lncli getchaninfo $chanid | jq -r '.node2_policy | .fee_rate_milli_msat'`
            else
                fees=`lncli getchaninfo $chanid | jq -r '.node1_policy | .fee_rate_milli_msat'`
            fi
        fi
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
        if [ "${chanid:0:1}" = "6" ];then fwdcount=`eval cat fwdlist.txt | grep -c -s $chanid`
            if [ "$fwdcount" -gt "0" ];then     cstate=$(echo "$cstate$fwdcount" ); fi; fi   
            if   [ "$init"   = "true" ];then balance=$(( $balance + $cf ))
            elif [ "$init"   = "false" ];then incoming=$(( $incoming + $cf ));fi
            if [ "$balance"   = "0" ];then balance="";fi
            if [ "$incoming"  = "0" ];then incoming="";fi
            if [[ -n "$incoming" ]];then incoming="          ${incoming}";incomingA="${incoming:(-9):3}";incomingB="${incoming:(-6):3}";incomingC="${incoming:(-3):3}";incoming="${incomingA// /} ${incomingB// /} ${incomingC// /}";incoming="${incoming/  /}";fi
            if [[ -n "$balance" ]];then abalance="           ${balance}";balanceA="${abalance:(-9):3}";balanceB="${abalance:(-6):3}";balanceC="${abalance:(-3):3}";balance="${balanceA// /} ${balanceB// /} ${balanceC// /}";balance="${balance/  /}";fi


            incoming="'\e[38;5;232m'_____________'\e[0m'${incoming}";incoming="${incoming:0:14}${incoming: -19}"
            balance="'\e[38;5;232m'_____________'\e[0m'${balance}";balance="${balance:0:14}${balance: -19}"
            #--------------display table size configurator
            OUTPUTME=`eval echo "'\e[38;5;$color'${chanid:0:2}'\e[0m'${chanid:2},$balance,$incoming,"$title",'\e[38;5;$ipcolor' $ipstatus'\e[0m',${cstate},$init,$thisconnectedcount,${thiscapacity:0:6},${avgchancap:0:6},${thisbiggestchan:0:6},$fees"`
            header="[38;5;232m02[0m Channel   ID,[38;5;232m[0mOutgoing,[38;5;232m[0mIncoming,Alias,[38;5;001m [0mType,[38;5;001m[0mActive,Init,Nodes,Capac.,AvgChan,Biggest,Fees (m msat)"
            echo "${OUTPUTME}" >> combined.txt
        done <nodelist.txt 3<pages/webdata.txt
        #----------START--DISPLAY & WAIT---------------------------------------------
        bosScore=$(curl https://nodes.lightning.computer/availability/v1/btc.json | jq '.scores[] | select(.alias == "eclips.lnd") | .score') 
        loop=`eval pgrep -x loopd >/dev/null && echo "OK" || echo "\e[31mKO"`
        pool=`eval pgrep -x poold >/dev/null && echo "OK" || echo "\e[31mKO"`
        echo -e "${header}\n`cat combined.txt|sort -d -i --field-separator=',' -k 7r,7r -k 6,6 -k 3 `"  | column -n -ts, > myout.txt  #main data table
        clear;  echo -e `cat myout.txt` #helps with screen refresh lag?  
        echo -e "  (${unconfirmed} unconf) (${limbo} in limbo$limbot) (${unset_balanceo} / ${unset_balancei} unsettled ${unset_times}) Recent fwds: ${fwding}"
        echo -e "In wallet: \e[38;5;45m${walletbal}\e[0m    Income (month) : \e[38;5;83m${income}\e[0m sat   Channels: \e[38;5;99m$(( $myrecs - 1))\e[0m (${reco}/${reci})   BOS score: $bosScore   LOOP : $loop   POOL : $pool"
        rm -f combined.txt myout.txt nodelist.txt rawout.txt rawoutp.txt fwdlist.txt
        secsi=$updatetimed;while [ $secsi -gt -1 ]; do echo -ne " Columns~"`tput cols`" [\e[38;5;${colorda}55\e[38;5;$colordb 80\e[38;5;$colordc 105\e[38;5;$colordd 135\e[0m and\e[38;5;$colorde 175\e[0m] "
        for (( c=1; c<=$(( $updatetimed - $secsi )); c++ )); do echo -ne " ";done ;  for (( c=1; c<=$(( $secsi )); c++ )); do echo -ne "»";done ;echo -ne " \e[38;5;173m$secsi\e[0m "
            for (( c=1; c<=$(( $secsi )); c++ )); do echo -ne "«";done ;echo -en "\033[0K\r\e[?25l"; if  [ $secsi -ne 0 ];then sleep 1;fi ; : $((secsi--));done   #countdown
        done
