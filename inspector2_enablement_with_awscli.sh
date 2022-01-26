#!/usr/bin/env bash

#
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# Amazon Inspector2 regions – by default empty, if the parameters file does not exist, then
# current region used for CLI is used as value. 
regions_to_activate=""

# The | account who will become the delegated administrator for Amazon Inspector2 
del_admin_inspector=""

# Configure the scanning type to be enable for new accounts that joined the org
default_auto_enable_conf="ec2=true,ecr=true" 
#Global variable
auto_enable_conf=""

# The scanning type to be enable/disable. Possible values are "ECR" | "EC2" | "EC2 ECR"
default_rsstype="EC2 ECR"
#Global variable 
rsstype=""

# Global variable Dry-run
dryrun="false"; 

# Global variable Parameter file where to read the value
params_file="./param_inspector2.json"

# Creation of a file to track the script execution
tmp_dir=$(mktemp -d -t inspector2-XXXXXXXXXX)
tmp_file_execution="$tmp_dir/inspector.txt"



###############------------------- useful functions  ----------------------#####################

check_aws_cli_version () {
    current_version=$(aws --version |  cut -d "/" -f 2 | cut -d " " -f 1)
    support_inspector2_cli1="1.22.16"; #https://github.com/aws/aws-cli/blob/develop/CHANGELOG.rst#12216
    support_inspector2_cli2="2.4.3";  #https://github.com/aws/aws-cli/blob/v2/CHANGELOG.rst#243
    current_awscli=$(aws --version |  cut -d "/" -f 2 | cut -c 1)
    awscliv2=false
    awscliv1=false
    versions=""
    awscliminversion=""

    case $current_awscli in
        "1")
            awscliv1=true
            versions=$(echo "$support_inspector2_cli1"; echo "$current_version")
            awscliminversion=$support_inspector2_cli1
            ;;
        "2")
            awscliv2=true;
            versions=$(echo "$support_inspector2_cli2"; echo "$current_version")
            awscliminversion=$support_inspector2_cli2
            ;;
        *)
            echo "unknown aws cli version ... EXITING NOW!!!"
            exit 1
        ;;
    esac;

    versionscheck=$((echo "$current_version" ; echo "$awscliminversion")|sort -V)


    if [ "${versions}" != "${versionscheck}" ] 
    then 
        echo "Usage of Amazon Inspector2 required an update of aws cli"
        echo "Please update AWS CLI version $current_awscli to minimum $awscliminversion. Current version : $current_version." 
        echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo ""
        exit 1
    fi
}

# Get the value of regions set as export variable or in the parameters file or use the default region the script is running in
get_regions_list(){
    default_region=""
    if [ "X$INSPECTOR2_REGIONS" == "X" ];then # check if INSPECTOR2_REGIONS variable is set in export variable
        if [ -f $params_file ]; then #if the file exist, then try to read the value set for regions in the file
            regions_in_file=$(cat $params_file | jq -r '.regions.enablement') 1>>$tmp_file_execution 2>>$tmp_file_execution
        else    
            regions_in_file=""
        fi
        if [ "X$regions_in_file" == "X"  ]; then # If regions is not set, then will use the current region where the script is executed
            default_region=$(aws configure list | grep region | awk '{print $2}') 1>>$tmp_file_execution 2>>$tmp_file_execution   
            regions_to_activate=$default_region
        else
            regions_to_activate=$regions_in_file
        fi 
    else
        regions_to_activate="$INSPECTOR2_REGIONS"
    fi
    #echo "$regions_to_activate"
    }

get_delegated_admin (){
    if [ "X$INSPECTOR2_DA" == "X" ];then #check if $INSPECTOR2_DA variable is set in export variable
        if [ -f $params_file ]; then
            da_in_file=$(cat $params_file | jq -r '.inspector2_da.id') 1>>$tmp_file_execution 2>>$tmp_file_execution
        else    
            da_in_file=""
        fi
        if [ "X$da_in_file" == "X"  ] || [ "$da_in_file" == "null"  ] ; then # if the da variable is not available in the file
            del_admin_inspector=""
        else
            del_admin_inspector="$da_in_file"
        fi 
    else
        del_admin_inspector="$INSPECTOR2_DA"
    fi
    echo $del_admin_inspector
    }


# Setting the value of DA for Inspector2 by updating the global variable value $del_admin_inspector. 
# Can now be used in all the script for all functions
get_delegated_admin
#Set value in global variable $regions_to_activate to be used all over the script for all the actions
get_regions_list


# Check if the current user is in the delegated admin or not
is_da_account(){
    check_result=""
    aws inspector2 get-delegated-admin-account 2>&1 |& grep -qs 'Invoking account is the delegated admin.'
    check_result=$(echo "$?")
    if [ "$check_result" == "0" ]; then 
        echo "$check_result" # this account is the DA: good
    else
        echo "1" # this account is not the DA: good
    fi
}

# Defining the auto-enable configuration by using the value in the parameters file
# Or the default value in default_auto_enable_conf
get_auto_enable_conf(){

    if [ -f $params_file ]; then
        autoenable_in_file=$(cat $params_file | jq -r '.auto_enable.conf') 1>>$tmp_file_execution 2>>$tmp_file_execution
    else    
        autoenable_in_file=""
    fi

    if [ "X$autoenable_in_file" == "X"  ] || [ "$autoenable_in_file" == "null" ]; then
        auto_enable_conf=$default_auto_enable_conf
    else
        auto_enable_conf=$autoenable_in_file
    fi 
    echo $auto_enable_conf
    }


# Get the scanning type to be enable/disable for Inspector2, using parameters set in the file
# Or use as default value $default_rsstype
get_scanning_type (){
    scantype2activate=""

    if [ "X$1" == "X"  ]; then ## An argument is not given
        if [ "X$scanning_in_file" == "X" ]; then
            #default value then
            rsstype=$default_rsstype
            echo $default_rsstype
        else
            if [ -f $params_file ]; then
                scanning_in_file=$(cat $params_file | jq -r '.scanning_type.selected') 1>>$tmp_file_execution 2>>$tmp_file_execution
            else    
                scanning_in_file=""
            fi
            rsstype=$scanning_in_file
            echo $scanning_in_file
        fi
    else #A scanning type is requested in command line
        case ${1} in
                "default" | "") rsstype=$default_rsstype; echo $default_rsstype;;
                "ec2" | "EC2")  rsstype="EC2"; echo "EC2";;
                "ecr" | "ECR")  rsstype="ECR"; echo "ECR";;
                "all" | "ALL")  rsstype="EC2 ECR"; echo "EC2 ECR";;
                *) echo "1" ;;
            esac
    fi 
    }

# Check if an account id valide: belong to the current AWS Organizations or well formatted
check_account_id (){
    check_accid_result=""
    acc_to_check="$1"
    aws organizations describe-account --account-id $acc_to_check 1>>$tmp_file_execution 2>>$tmp_file_execution 
    check_accid_result=$(echo "$?")
    if [ $check_accid_result == "0" ]; then
        echo "0" # good, real | account and members of AWS Org
    else 
        echo "1" # either bad format or not member of the same AWS Org
    fi
    }

# Guide - help
get_guide () {
    echo "To manage Amazon Inspector2, use one of the following argument. [ ] is optional."
    echo "Check Status       :  -a get_status"
    echo "Activation phase   :  -a delegate_admin -da ACCOUNT_ID"
    echo "Activation phase   :  -a activate -t members|ACCOUNT_ID [-s ec2|ecr|all]"
    echo "Activation phase   :  -a associate -t members|ACCOUNT_ID "
    echo "Activation phase   :  -a auto_enable [-e \"ec2=true,ecr=true\"]"
    echo "Deactivation phase :  -a deactivate -t members|ACCOUNT_ID [-s ec2|ecr|all]"
    echo "Deactivation phase :  -a disassociate -t members|ACCOUNT_ID "
    echo "Deactivation phase :  -a remove_admin -da ACCOUNT_ID"
    echo ""
    echo "Example of execution with dryrun    : $0 -a get_status --dryrun or $0 -a get_status -r" 
    echo "Example of execution without dryrun : $0 -a get_status"
    echo "Dry-run is available for each command."
}

# Get the target on which the actions will applied : accountid | members
get_target () {
    target_arg="$1"
    case "${target_arg}" in
        "members")
            if [ $(is_da_account) == "0" ]
            then 
                current_acc=$(aws sts get-caller-identity | jq -r '.Account'); #a member will only be able to see its own status
                # Accounts lists members of AWS Organizations except the delegated administrator 
                member_list_inspector=$(aws organizations list-accounts | jq --arg jq_var "${current_acc}" -r '.Accounts[].Id | select(. != $jq_var)')
                echo "$member_list_inspector"
            else
                echo "$target_arg"
            fi
        ;;
        "" | " ") echo "1" ;;
        *) echo "$target_arg" ;;
    esac
}

###############------------------- Functions to get  ----------------------#####################
#STEP0 : PRE-CHECK|POST-CHECK ACTIVATION STATUS OF AMAZON INSPECTOR2
# For each account, and in each listed regions, check if Amazon Inspector2 is enabled
check_inspector2_status_per_region () {
    inspector2_account_status=""
    inspector2_account_status_failed=""
    target_to_status=""
    ecr_status=""
    ec2_status=""
    check_get_code="1"
    current_acc=$(aws sts get-caller-identity | jq -r '.Account')
    org_list_account=$(aws organizations list-accounts | jq -r '.Accounts[].Id')

    if [ $(is_da_account) == "0" ] ##the current account is the Inspector2 DA account
    then 
        #list of accounts on AWS Organizations
        list_accounts=$(aws organizations list-accounts | jq -r '.Accounts[].Id') 1>> $tmp_file_execution 2>> $tmp_file_execution
        target_to_status=$list_accounts; #Only the DA can accurately check the status of all accounts
    else
        target_to_status=$(aws sts get-caller-identity | jq -r '.Account')  #a member will only be able to see its own status
    fi

    for i in $target_to_status;  do  
        inspector2_account_status=""
        echo"";echo " ******** Checking the activation status of Amazon Inspector2 for account $i per regions ******** "

        for region in $regions_to_activate; do
            if [ "$dryrun" == "true" ]
            then
                echo "aws inspector2 batch-get-account-status --account-ids $i --region $region"
            else
                aws inspector2 batch-get-account-status --account-ids $i --region $region 1>> $tmp_file_execution 2>> $tmp_file_execution
                check_get_code=$(echo $?)
                if [ "$check_get_code" == "0" ];then
                    inspector2_account_status=$(aws inspector2 batch-get-account-status --account-ids $i --region $region | jq -r '.accounts[].state.status')  
                    if  [ "X$inspector2_account_status" == "X" ]; then 
                        inspector2_account_status_failed=$(aws inspector2 batch-get-account-status --account-ids $i  --region $region | jq -r '.failedAccounts[].errorCode') 1>> $tmp_file_execution 2>> $tmp_file_execution
                        if [ "$inspector2_account_status_failed" == "ACCESS_DENIED" ]; then 
                            echo "For Account $i in $region: Amazon Inspector2 status is DISASSOCIATED."
                        else
                            ecr_status=$(aws inspector2 batch-get-account-status --account-ids  $i  --region $region | jq -r '.accounts[].resourceState.ecr.status')  
                            ec2_status=$(aws inspector2 batch-get-account-status --account-ids  $i  --region $region | jq -r '.accounts[].resourceState.ec2.status') 
                            echo "For Account $i in $region: Amazon Inspector2 status is $inspector2_account_status - ECR is $ecr_status - EC2 is $ec2_status";
                        fi
                        inspector2_account_status_failed=""
                    elif  [ "$inspector2_account_status" == "DISABLED" ]; then 
                        ecr_status="DISABLED";ec2_status="DISABLED"
                        echo "For Account $i in $region: Amazon Inspector2 status is $inspector2_account_status - ECR is $ecr_status - EC2 is $ec2_status"
                    else
                        ecr_status=$(aws inspector2 batch-get-account-status --account-ids  $i  --region $region | jq -r '.accounts[].resourceState.ecr.status')  
                        ec2_status=$(aws inspector2 batch-get-account-status --account-ids  $i  --region $region | jq -r '.accounts[].resourceState.ec2.status')  
                        echo "For Account $i in $region: Amazon Inspector2 status is $inspector2_account_status - ECR is $ecr_status - EC2 is $ec2_status"
                    fi
                else
                    echo "For Account $i in $region: Amazon Inspector2 status is unknown. Check the execution file."
                fi
                inspector2_account_status=""
                ecr_status=""
                ec2_status=""
            fi
            sleep 0.1;
        done
    done
}


####@@@@@@@@@@@  ------- Activation of Inspector2 and Association of members from the DA 

####STEP2 : ACTIVATION OF Inspector2 PER REGION. BASED ON THE ACCOUNTS LIST OR ACCOUNT-ID
enable_inspector2_per_region() {
    target_to_activate=""
    argument_activate=$1
    scantype2activate=""
    scan2activate=$2
    is_da="1"

    #########--------->Target to apply the action on
    target_to_activate=$(get_target $argument_activate)
    if [ "$target_to_activate" == "1" ]; then
        echo "Unexpected argument passed : $target_to_activate. Argument expected : members | account-id. "
        exit 1
    fi

   #########--------->Scan to activate
    scantype2activate=$(get_scanning_type $scan2activate)
    if [ "$scantype2activate" == "1" ]; then
        echo "Unexpected argument passed : $scantype2activate. Possible values are : ec2 | ecr | all. "
        exit 1
    fi

    echo"";echo " ******** Activation of Inspector2 for accounts per regions ******** "
    echo "[ACCOUNTS_LIST]:"$target_to_activate
    is_da="$(is_da_account)"
    for region in $regions_to_activate; do
        if [ "$dryrun" == "true" ]
        then
            echo "aws inspector2 enable --account-ids [ACCOUNTS_LIST] --resource-types $scantype2activate --region $region"
        else
            if [ $is_da == "0" ]; then
                echo "Attemting to enable Inspector2 in accounts for the scanning type $scantype2activate in region $region;"
                aws inspector2 enable --account-ids $target_to_activate --resource-types $scantype2activate --region $region 1>> $tmp_file_execution 2>> $tmp_file_execution; sleep 0.2
            else
                echo "Log in DA account to enable Amazon Inspector2 on $target_to_activate account(s)."
            fi
        fi
    done
}

####STEP 4: ASSOCIATING MEMBER TO THE ADMINISTRATOR ACCOUNT PER REGION
# For each account, and in each listed regions, associate the account to Inspector2 administrator accounts
attach_member_to_inspector2_admin_per_region () {
    target=""
    argument_target=$1
    check=""
    deleg_admin_found=""
    target=""
    argument_target=$1
    current_acc=""
    #Exit if the current account is not the DA, since the association must be done by the DA account
    if [ "$(is_da_account)" != "0" ]; then 
        # If it is not the DA account, then exit with error
        echo "Can only be done from the delegated admin (DA) account! Please log in your DA account."
        exit 1
    fi
   
    #########--------->Target to apply the action on
    target=$(get_target $argument_target)
    current_acc=$(aws sts get-caller-identity | jq -r '.Account')
    if [ "$target" == "1" ] || [ "$target" == "admin" ] || [ "$target" == "$current_acc" ] ; then
        echo "Unexpected argument passed. Argument expected : members|account-id. Please see the execution file. "
        exit 1
    fi

    for i in $target;  do  
        echo"";echo " ******** Checking the member status of Amazon Inspector2 for account $i per regions ******** "
        for region in $regions_to_activate; do
            if [ "$dryrun" == "true" ]
            then
                echo "aws inspector2 associate-member --account-id $i --region $region"
            else
                echo "Attempting to associate account $i to Inspector2 Administrator in region $region"
                aws inspector2 associate-member --account-id $i --region $region 1>>$tmp_file_execution 2>>$tmp_file_execution
                sleep 0.1
            fi
            check=""
        done
    done
    echo "Wait a few minutes for the association to be completed.";echo "Check the result in the console, or run \"aws inspector2 list-members \""
}
   

## STEP 1: ASSIGNING INSPECTOR2 ADMINISTRATOR ACCOUNT PER REGION
designated_delegated_admin_for_inspector2(){
    check_accid=""
    local_del_admin=""
    current_acc=""
    if [ "x$1" == "x" ];then #No argument given with -da option
        local_del_admin=$(get_delegated_admin)
    else
        local_del_admin="$1" #use the argupment given with -da
    fi
    if [ "x$local_del_admin" == "x" ]; then
        check_accid="1"
    else 
        check_accid=$(check_account_id $local_del_admin)
    fi
    echo"";echo " ******** Designate $local_del_admin account as  Amazon Inspector2 Administrator per regions ******** "

    check_accid=$(check_account_id $local_del_admin)
    if [ "$check_accid" == "0" ]; then
        #Master | account of AWS Organizations from where the delegation of admin can take place
        master_account=$(aws organizations describe-organization --query Organization.MasterAccountId --output text)    
        current_acc=$(aws sts get-caller-identity | jq -r '.Account')
        for region in $regions_to_activate; do
            if [ "$dryrun" == "true" ]
            then
                echo "aws inspector2 enable-delegated-admin-account --delegated-admin-account-id $local_del_admin --region $region"
            else
                if [ $current_acc == $master_account ]
                then 
                    echo "Attempting to assign $local_del_admin as Inspector2 Administrator Account in region $region."
                    aws inspector2 enable-delegated-admin-account --delegated-admin-account-id $local_del_admin --region $region 1>>$tmp_file_execution 2>>$tmp_file_execution                    
                else
                    echo "Please log as in the master account $master_account to successfully executed this command."
                fi
            fi
            sleep 0.1
        done
        echo "";echo "Use the console or Run \"aws inspector2 list-delegated-admin-accounts\" to check the result."
    else        
        echo "--------- CAUTION ---------"; echo "You provided an accountid $local_del_admin that does not meet the requirements. Please see the execution file." 
        echo "export INSPECTOR2_DA=\"DA_ACCOUNTID\" or set the right account id in $0 -a $actionselected -da DA_ACCOUNTID or check your permissions";
    fi

 }   


####STEP3 : AUTO-ENABLEMENT OF INSPECTOR2 - FOR NEW ACCOUNTS
autoenable_inspector2_for_new_accounts() {
    check_result=""
    if [ "X$1" == "X" ]; then #parameter in argument is empty
        #Set value in global variable $regions_to_activate to be used all over the script for all the actions
        get_auto_enable_conf
    else
        echo "$1" | grep "ec2" | grep "ecr" | grep "true"  1>>$tmp_file_execution 2>>$tmp_file_execution
        check_result=$(echo "$?")
        if [ "$check_result" == "0" ]; then
            auto_enable_conf="$1"
        fi
    fi
    
    
    echo"";echo " ******** Auto-enablement of Inspector2 for new accounts per regions ******** "

    for region in $regions_to_activate; do
        if [ "$dryrun" == "true" ]
        then
            echo "aws inspector2 update-organization-configuration --auto-enable $auto_enable_conf --region $region"
        else
            if [ "$(is_da_account $region)" == "0" ]
            then 
                echo "Attempting to configure auto-enablement of Inspector2 in new accounts in region : $region"
                aws inspector2 update-organization-configuration --auto-enable $auto_enable_conf --region $region 1>>$tmp_file_execution 2>>$tmp_file_execution
            else
                echo "Log into Delegated Admin account to proceed with Inspector2 auto-enablement.";echo "";echo ""
                exit
            fi
        fi
        sleep 0.2    
    done
}


####@@@@@@@@@@@  ------- Deactivation of Inspector2 and Disassociation of members from the DA 

####DEACTIVATION DE INSPECTOR in ACCOUNTS, per SCANNING TYPE and in ALL REGIONS
disable_inspector2_per_region() {
     target_to_deactivate=""
    argument_deactivate=$1
    scantype2deactivate=""
    scan2deactivate=$2
    is_da=""

    #########--------->Target to apply the action on
    target_to_deactivate=$(get_target $argument_deactivate)
    if [ "$target_to_deactivate" == "1" ]; then
        echo "Unexpected argument passed : $argument_deactivate. Argument expected : members | account-id."; exit 1
    fi

   #########--------->
    scantype2deactivate=$(get_scanning_type $scan2deactivate)
    if [ "$scantype2deactivate" == "1" ]; then
        echo "Unexpected argument passed : $scantype2deactivate. Possible values are : ec2 | ecr | all. "; exit 1
    fi

    echo"";echo " ******** Deactivation of Amazon Inspector2 for accounts listed below per regions ******** "
    echo "[ACCOUNTS_LIST]: "$target_to_deactivate;echo""

    for region in $regions_to_activate; do
        if [ "$dryrun" == "true" ]
        then echo "aws inspector2 disable --account-ids [ACCOUNTS_LIST] --resource-types $scantype2deactivate --region $region; "
        else 
            if [ "$(is_da_account)" == "0" ]; then
                echo "Attemtping to disable Amazon Inspector2 in accounts [ACCOUNTS_LIST] for scanning type $scantype2deactivate  in region $region."
                aws inspector2 disable --account-ids $target_to_deactivate --resource-types $scantype2deactivate --region $region  1>> $tmp_file_execution 2>> $tmp_file_execution; sleep 0.2 
            else
                echo "Log in DA account to disable Amazon Inspector2 on $target_to_activate account(s)."
            fi
        fi               
    done

 
 } 


###### DISASSOCIATION ACCOUNTS TO ANY MASTER IN THE LISTED REGIONS
detach_members_to_designated_admin_inspector2 (){
    target=""
    argument_target=$1
    memberstatus=""
    membership_status=""
    current_acc=""

    target=""
    argument_target=$1
   
    if [ "$(is_da_account)" == "1" ]; then 
        # If it is not the DA account, then exit with error
        echo "Can only be done from the delegated admin (DA) account! Please log in your DA account."
        exit 1
    fi
   
    #########--------->Target to apply the action on
    target=$(get_target $argument_target)
    current_acc=$(aws sts get-caller-identity | jq -r '.Account')
    if [ "$target" == "1" ] || [ "$target" == "admin" ] || [ "$target" == "current_acc" ] ; then
        echo "Unexpected argument passed. Argument expected : members | account-id. Please at the execution file. "
        exit 1
    fi

    for i in $target; do  
        echo"";echo " ******** Disassociating of account $i to any Master of Inspector2 ******** "
        for region in $regions_to_activate; do
            if [ "$dryrun" = "true" ]; then
                echo "aws inspector2 disassociate-member --account-id $i --region $region"
            else    
                echo "Attempting to disassociate this account $i from DA in : $region."
                aws inspector2 disassociate-member --account-id $i --region $region 1>> $tmp_file_execution 2>> $tmp_file_execution;sleep 0.1
            fi              
        done
    done
    echo "";echo "Check the result in the console, or run \"aws inspector2 list-members\""

 } 


## REMOVE INSPECTOR2 DELEGATED ADMINISTRATOR
remove_delegated_admin_for_inspector2(){
    #Master account of AWS Organizations from where the delegation of admin can take place
    
    check_accid=""
    local_del_admin=""
    check_da=""
    
    if [ "x$1" == "x" ];then
        #local_del_admin="$del_admin_inspector"
        local_del_admin=$(get_delegated_admin)
    else
        local_del_admin="$1"
    fi
    if [ "x$local_del_admin" == "x" ]; then
        check_accid="1"
    else 
        check_accid=$(check_account_id $local_del_admin)
    fi
    echo "";echo " ******** Remove $local_del_admin account as Amazon Inspector2 Administrator per regions ******** "    

    if [ "$check_accid" == "0" ]; then
        master_account=$(aws organizations describe-organization --query Organization.MasterAccountId --output text)
        current_acc=$(aws sts get-caller-identity | jq -r '.Account')
        #echo "Enter a delegated acc  check_accid = $check_accid" 
        for region in $regions_to_activate; do
            if [ "$dryrun" == "true" ]
            then
                echo "aws inspector2 disable-delegated-admin-account --delegated-admin-account-id $local_del_admin --region $region"
            else
                if [ $current_acc == $master_account ]
                then 
                    echo "Attempting to remove $local_del_admin as delegated administrator in region $region "
                    aws inspector2 disable-delegated-admin-account --delegated-admin-account-id $local_del_admin --region $region 1>>$tmp_file_execution 2>>$tmp_file_execution
                else
                    echo "Please log as in the master account $master_account to successfully executed this command in region : $region."
                fi
            fi
            sleep 0.1
        done
        echo "";echo "CAUTION: If you are sure you want to remove the DA at the organization level for all regions run \"aws organizations deregister-delegated-administrator --service-principal inspector2.amazonaws.com --account-id $local_del_admin\"."
    else        
       echo "--------- CAUTION ---------"; echo "You provided an accountid $local_del_admin that does not meet the requirements. Please see the execution file."
        echo "export INSPECTOR2_DA=\"DA_ACCOUNTID\" or set the right account id in $0 -a $actionselected -da accountid";
    fi
 }



## --------------------------------------- MAIN ----------------------------------------##

# Loop until all parameters are used up
cpt=1
nbarg="$#"
dryrunselected=""
actionselected=""
targetselected=""
scanningselected=""
autoconfselected=""
adminselected=""

# Check the AWS CLI version before starting 
check_aws_cli_version

while [[ "$#" -gt 0 ]]; do
    case $1 in
        "-a"|"--action") 
                actionselected="$2"; 
                if [ "x$actionselected" == "x" ] || [ "$actionselected" == "--dry-run" ] || [ "$actionselected" == "-r" ] || [ "$actionselected" == "-t" ]  || [ "$actionselected" == "--target" ] ;then 
                    actionselected="-h"
                    get_guide ## Information on how to use the script
                    exit 1
                fi
                shift; shift
            ;;
        "-t"|"--target") 
                targetselected="$2"
                case $targetselected in 
                    " " | "" | "-r" | "--dry-run" | "-a" | "-s")
                        echo "The target is not set. Restart with : $0 -a $actionselected -t accountid|members";
                        exit 1
                        ;;
                    * | "admin" | "members")
                        shift;shift 
                        ;;
                esac
            ;;
        "-s"|"--scanning") 
                scanningselected="$2"
                if [ "x$scanningselected" == "x" ] || [ "$scanningselected" == "--dry-run" ] || [ "$scanningselected" == "-r" ];then 
                    echo "The scanning is not set. Default value applied : $default_rsstype"
                    scanningselected="" #reinitialization the variable scan type
                    shift
                else
                    shift ;shift
                fi;
            ;;
        "-e"|"--auto-enable") 
                autoconfselected="$2"
                if [ "x$autoconfselected" == "x" ] || [ "$autoconfselected" == "--dry-run" ] || [ "$autoconfselected" == "-r" ];then 
                    echo "The auto-enablement configuration is not set. Default value applied : $default_auto_enable_conf"
                    autoconfselected="" #reinitialization the variable auto-enable
                    shift
                else
                    shift ;shift
                fi;
            ;;
        "-da"| "--deleg_admin") adminselected="$2"; shift;shift ;;
        "-r" | "--dry-run") dryrunselected="--dry-run"; shift;;
        "-h" | "help") 
            actionselected="-h"
            get_guide ## Information on how to use the script
            exit 1
            ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done


# Let's check if it is a dryrun or no
if [ "$dryrunselected" == "--dry-run" ]
then 
    dryrun="true"
    echo "< -------------------------------- Dry Running -------------------------------- >"
fi


date >> $tmp_file_execution
echo "" >> $tmp_file_execution


### What action will be executed?
case $actionselected in
    "" | "help" | "-h")
        get_guide ## Information on how to use the script
    ;;
    "get_status")
        echo "check_inspector2_status_per_region"
        check_inspector2_status_per_region
    ;;
    "activate")
        echo "enable_inspector2_per_region $targetselected $scanningselected"
        enable_inspector2_per_region "$targetselected" "$scanningselected" #$dryrun
    ;;
    "delegate_admin")
        echo "designated_delegated_admin_for_inspector2 $adminselected"
        designated_delegated_admin_for_inspector2 "$adminselected" #$dryrun
    ;;
    "auto_enable")
        echo "autoenable_inspector2_for_new_accounts $autoconfselected"
        autoenable_inspector2_for_new_accounts $autoconfselected #$dryrun
    ;;
    "associate")
        echo "attach_member_to_inspector2_admin_per_region $targetselected"
        attach_member_to_inspector2_admin_per_region "$targetselected"
    ;;  
    "disassociate")
        echo "";echo "detach_members_to_designated_admin_inspector2 $targetselected";
        detach_members_to_designated_admin_inspector2 "$targetselected"
    ;;
    "remove_admin")
        echo "REMOVING Amazon Inspector2 administrator account for all regions at once"
        remove_delegated_admin_for_inspector2 "$adminselected"
    ;;
    "deactivate")
        echo "disable_inspector2_per_region $targetselected $scanningselected"
        disable_inspector2_per_region "$targetselected" "$scanningselected"
    ;;
    *)
        echo "unknown parameter ... EXITING NOW!!!"
        echo "Run for relevant command: $0 -h"
        exit 1
    ;;
esac
echo "";date >> $tmp_file_execution; echo ""
echo "Execution details here: $tmp_file_execution"
echo ""
exit 0
