# 0. Important
## 0.1. Amazon Inspector2 prerequites
For Amazon Inspector2 to run CVE assessment, SSM Agent needs to be installed and [enabled](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up.html) on the EC2 as per the [documentation](https://docs.aws.amazon.com/inspector/latest/user/getting_started_tutorial.html). By **SSM Agent enabled**, ensure that AWS System Manager is deployed and can communicate with your EC2 having the adequate instance profile. 

## 0.2. Note 
- If you have questions regarding Amazon Inspector2, please reach out the product team by opening a ticket. 
- If you have questions regarding the script, you can contact the script author.

# 1. Purpose
This script will help to deploy Amazon Inspector2 (released the 29th november 2021) across an AWS Organizations in multiple regions. The script uses Amazon Inspector2 AWS CLI commands to loop on accounts and in the specified regions.

# 2. Pre-requisites
Below the prerequites in order to successfully run the script to deploy Amazon Inspector2.

Using this script, it is assumed you have met the prerequites in the Amazon Inspector2 [official documentation](https://docs.aws.amazon.com/inspector/latest/user/getting_started_tutorial.html). 

## 2.1. AWS CLI 
### 2.1.1.  AWS CLI version
The below versions at the minimum expected to use Amazon Inspector2 CLI reference:
- For AWS CLI 1, install at least version [1.22.16](https://github.com/aws/aws-cli/blob/develop/CHANGELOG.rst#12216)
- For AWS CLI 2, install at least version [2.4.3](https://github.com/aws/aws-cli/blob/v2/CHANGELOG.rst#243)
Note : The script works with CLI version 1 and CLI version 2. The script checks AWS CLI version when running.

### 2.1.2.  jq
`jq` is used in the script, so please install [jq](https://stedolan.github.io/jq/download/). 

## 2.2. AWS Organizations
AWS Organizations is mandatory. The delegation of Amazon Inspector2 Delegated Administrator (DA) can only be done from the managment account.

## 2.3. Access and permissions
### 2.3.1. Access to the Organizations management account
From the Organization management account, designate a Delegated Admininistrator for Amazon Inspector2. 

### 2.3.2. Access the Delegated Admininistrator (DA)
The effective management of Amazon Inspector2 will be done from this account.

### 2.3.3. Permissions to designate a DA
You must have permission to designate an Amazon Inspector delegated administrator. Add this [statement](https://docs.aws.amazon.com/inspector/latest/user/delegated-admin-permissions.html) to the end of an IAM policy to grant these permissions.

### 2.3.4 Permissions to manage Inspector2
Attach the [AmazonInspector2FullAccess](https://docs.aws.amazon.com/inspector/latest/user/security-iam-awsmanpol.html#security-iam-awsmanpol-AmazonInspector2FullAccess) managed policy to your IAM identities to grant full access to Amazon Inspector2 for its management. 

## 2.4. Variables
### 2.4.1 Default variables
Below are the default variables in the script :
- `$default_auto_enable_conf`       : Configure the scanning type to be enable for new accounts that are attached to the DA. You must always set the value for both ec2 and ecr. By default in the script, the value is set : `auto_enable_conf="ec2=true,ecr=true"`
- `$default_rsstype`                : Inspector2 scanning type to be enable. The default value is set to `"EC2 ECR"`.

### 2.4.2 Variables to set in the parameters file 
Below are the variables in the `param_inspector2.json` that you will need to update according to your Organization:
- `inspector2_da.id`       : AWS Account id you want to designate as Delegated Admin for Amazon Inspector2
- `scanning_type.selected` : Inspector2 scanning type to be enable. Possible values are "ECR" | "EC2" | "EC2 ECR"
- `auto_enable.conf`       : Configure the scanning type to be enable for new accounts that are attached to the DA. You must always set the value for both ec2 and ecr. Example : `auto_enable.conf="ec2=true,ecr=true"`
- `regions.enablement`     : The list of AWS regions where you want to enable/disable Amazon Inspector2. Example in the parameters file. If empty, then the script will use the current region

### 2.4.3 Export the variables
If you do not want to update the values in the `param_inspector2.json`, you can export the variables values:
- `export INSPECTOR2_DA="DA_ACCOUNTID"`
- `export INSPECTOR2_REGIONS="eu-west-1 us-east-1 eu-central-1"`


# 3. Script execution
The script runs locally using AWS CLI and works also on CloudShell. Maybe the easiest way to run it, by uploading the scriptsfor the customer. 
If you have designated an account different than the Management Organization Account as "Delegated Administrator" for Amazon Inspector2, you will need to :
1. run the script in the Management Organization Account : As per the security principle, only this account can designate another account as admin
2. run the script (the same one) in the Delegated Administrator account to manage Amazon Inspector2 : enable/disable, configure auto-enable, attach/detach members...

If you have designated the Management Organization account as the Delegated Admininistrator for Amazon Inspector2, then run all the steps of the script in only that account.


## 3.1. script parameters
If you run the script with no parameters you will see the list of options. As per below:
```
> To manage Amazon Inspector2, use one of the following argument. 
> Check Status       :  get_status
> Activation phase   :  delegate_admin
> Activation phase   :  activate_admin
> Activation phase   :  auto_enable
> Activation phase   :  attach_members
> Activation phase   :  activate_scan_accountid
> Deactivation phase :  deactivate_members
> Deactivation phase :  detach_members
> Deactivation phase :  deactivate_admin
> Deactivation phase :  remove_admin
```

## 3.2. Dry run
`--dry-run` | `-r` option is available for each command. 

## 3.3. Example of script usage
`./script_name.sh delegate_admin --da ACCOUNTD_ID --dry-run`
 
`./script_name.sh activate -t ACCOUNT_ID -s all `


# 4. Activation phase
Amazon Inspector2 would be enabled in all accounts, regions with the scan type you configured in the variales. 

![Activation phase using the script](Inspector2_script_activation.png)

If your Delegated Admininistrator (DA) account is different than your management Organization account, then after step 1, log into your DA account. If not, continue the next steps in the same account.
You will need to execute the steps 2, 3 and 4 in the DA account as shown in the table below.
Caution: **Wait a few minutes** after step 4 to check the status with `get_status`. You can check the progress through the console while the script is running.

| N°     | Run the script in | Parameters | Description | 
| ------ | ------ | ------ | ------ |
| 1   | Management Organization account | `delegate_admin -da DA_ACCOUNT_ID` | designate `DA_ACCOUNT_ID` as Inspector2 DA for AWS Organizations |
| 2   | Delegated Administrator Account | `activate -t DA_ACCOUNT_ID -s all` | Activate Inspector2 on the DA account for EC2 & ECR scans|
| 3   | Delegated Administrator Account | `auto_enable` | Configure auto-enablement of Inspector2 on the accounts attached to the DA |
| 4   | Delegated Administrator Account | `attach -t members` | Attach the member accounts to the DA account |

Wait a few minutes for the Amazon Inspector2 to be enable in all the accounts and regions configured.

In the DA Account, execute the script with `get_status` to get the Inspector2 activation status of accounts attached to the DA account.


# 5. Deactivation phase
For Inspector2 deactivation, you will need to follow the steps below.

![Deactivation phase using the script](Inspector2_script_deactivation.png)

| N°     | Run the script in | Parameters | Description | 
| ------ | ------ | ------ | ------ |
| 5   | Delegated Administrator Account | `deactivate -t members -s all` | deactivate Inspector2 by removing all scans types from members accounts |
| 6   | Delegated Administrator Account | `detach_members -t members` | Detach the memebers accounts from the DA account|
| 7   | Delegated Administrator Account | `deactivate -t DA_ACCOUNT_ID -s all` | Deactivate Inspector2 on the DA account|
| 8   | Management Organization account| `remove_admin -da DA_ACCOUNT_ID` | Remove DA account  |

Wait around 5 minutes after step 5 and then check the status with `get_status`. 
Optionally, wait around 5 minutes after step 6 and then check the status with `get_status`. 
Connect to the Management Organization account for step 8.


## My Project

TODO: Fill this README out!

Be sure to:

* Change the title in this README
* Edit your repository description on GitHub

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
