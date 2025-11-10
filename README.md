# Alteon-ACME-CertAutomation #
This solution allows you automating the renewal certificate process using ACME

## Table Of Contents ###
- [Description](#description)
- [Pre Requisites](#Pre-Requisites)
- [How To Use](#how-to-use)
- [Limitation](#Limitation)
- [Disclaimer](#Disclaimer)

## Description ##
* Objective: Automating the renewal of SSL/TLS certificates for Alteon devices managed by Cyber Controller
* ACME Client: Utilizing 'dehydrated' for managing the lifecycle of certificates via Let's Encrypt Certificate Authority (CA)
* Challenge Deployment: Utilizing the HTTP-01 challenge type, deploying and cleaning each domain's challenge into the Alteon devices to validate domain ownership before certificate issuance
* Certificate Provisioning: Automatically provisioning new certificates on designated Alteon devices upon successful renewal
* Logging: Maintaining detailed log files to track and review the last certificates renewal process
* Notifications: Sending email notifications upon completion, detailing success, unchanged or failure of the certificate renewal process
* In the event that Cyber Controller is unavailable, the secondary Cyber Controller server will send an email notification about that issue

## Pre Requisites ##
*   At least one Cyber Controller server version 10.5 and above, with internet connectivity
*	The Alteon's virtual servers should be accessible from the Internet
*	Public DNS record for each virtual server for validation by ACME
*	Office365 account for sending email notifications

## How To Use ##
1. Get the files with git or download them manually, example how to get that using git command from the Cyber-Controller:

```
cd /etc
git clone https://github.com/Radware/Alteon-ACME-CertAutomation.git
cd /etc/Alteon-ACME-CertAutomation
```

2. In case of downloading the files manually, upload the files to the Cyber-Controller Linux

```
mkdir /etc/Alteon-ACME-CertAutomation
cd /etc/Alteon-ACME-CertAutomation
```

3. Grant executable permission to the following files:

```
chmod +x hook.sh dehydrated renew_certificates_for_alteon_using_ACME.sh check_the_primary_cc_and_send_mail_if_needed.sh
```

4. Upload the **Alteon_Deploy_Certificate.vm**, **Alteon_Deploy_ACME_Challenge.vm**, and **Alteon_Clean_ACME_Challenge.vm** configuration templates to Cyber Controller vDirect:

![image](https://github.com/user-attachments/assets/8164430f-0eb5-45ca-9078-84274b779b8c)

![image](https://github.com/user-attachments/assets/40fa2d1c-ac24-4d5b-ba40-ff68573a711c)

![image](https://github.com/user-attachments/assets/16e481df-fbcf-43c2-9eb2-b538517f8682)

Alternatively, you can choose **Create a new template** and paste the configuration files content, make sure provide the exact names.

Repeat this process for the secondary Cyber Controller server.

5. Edit the **config** file and modify the required parameters from their defaults, if necessary (such as the Let’s Encrypt URL, key size, key algorithm RSA/ECC parameters).

6. Edit the hook.sh file and modify the Cyber Controller vDirect parameters according to your setup. For example:

    a. PRIMARY_CC_IP="10.0.0.100"

    b. PRIMARY_CC_USER="ACME-User"

    (the password will not be writen in the file)
  
    c. SECONDARY_CC_IP="10.0.0.200"
  
    d. SECONDARY_CC_USER="ACME-User"
  
    (the password will not be writen in the file)
  
    e. INSECURE=false

7. Copy the **letsencrypt-validation.tcl** AppShape++ script to the Alteon device, name it “letsencrypt-validation” and associate it to service 80 under the virtual servers that should eventually have service 443 with the Let’s Encrypt signed certificate

The virtual server should be accessible by letsencrypt with the virtual server DNS name.

8. Edit the **renew_certificates_for_alteon_using_ACME.sh** file and edit the following:

    a. SENDER_EMAIL="sender_email@company.com" -- provide the sender email.
  
    b. RECIPIENT_EMAIL="recipient_email@company.com" -- provide the recipient email.
  
    c. For additional recipients, follow the example below in the code.

9.	Testing the solution:

    a. Edit the **domains.txt** file and provide a test-domain
  
    b. Edit the **config** file and make sure that the CA is the staging ACME CA - CA="https://acme-staging-v02.api.letsencrypt.org/directory".
  
    c. Edit the **alteon_devices_per_domains.json** file and map the Alteon management IP addresses to the domains.txt file. For example:
  
      {
        "domains.txt": "10.0.0.1,10.0.0.2"
      }

      To gather the Alteon IP addresses, you can log in to vDirect and navigate to Inventory > ADCs.
      For example:
      
      ![image](https://github.com/user-attachments/assets/4e76a8a9-fc0e-49f3-80e2-a23956295e55)

    d.	Export the **primary_cc_password_for_ACME**, **secondary_cc_password_for_ACME** (optional), **https_proxy** (optional), and **sender_password_for_ACME** (for sender_email@company.com) as environment variables to avoid setting them as plaintext in the code:
  
      ```
      export primary_cc_password_for_ACME='password'
      export secondary_cc_password_for_ACME='password' (optional)
      export https_proxy='http://user:password@host:port' (optional)
      export sender_password_for_ACME='password'
      ```
      
      In Addition, export the **ALTEON_DEVICES**
      
      ```
      export ALTEON_DEVICES='10.0.0.1,10.0.0.2'
      ```
      
    e.	Before running dehydrated for the first time against the Let’s Encrypt CA (or other CA that supports ACME protocol), run the following command:
  
      ```
      bash /etc/Alteon-ACME-CertAutomation/dehydrated --register --accept-terms
      ```
      
    f.	Run dehydrated manually:
  
      ```
      bash /etc/Alteon-ACME-CertAutomation/dehydrated -c -x -g
      ```
      
    g.	Run the bash script, now the email should be sent to the recipient:
  
      ```
      bash renew_certificates_for_alteon_using_ACME.sh
      ```
      
10.	Implementing the solution:
    
    a. Modify the **domains.txt** file with the list of domains for which you want to receive signed certificates from Let’s Encrypt.
  	
    b. In case you have different domain lists that use different Alteon devices, create domains TXT file for each environment, and edit the alteon_devices_per_domains.json file to map the Alteon devices to the relevant domains TXT file. For example:

    ```
    {
      "domains_env1.txt": "10.0.0.1,10.0.0.2",
      "domains_env2.txt": "10.0.0.3,10.0.0.4"
    }
  	```
    
    Note: Every line should begin with a domain that will be used as the CN (Common Name) for the certificate and with optional additional domains that will be used as SAN (Subject Alternative Names).
    
    c. Edit the **config** file and make sure that the CA is the production ACME CA:
  	
    CA="https://acme-v02.api.letsencrypt.org/directory"
  	
    d.	Again run the following command to register to the production ACME CA:
  	
    ```
    bash /etc/Alteon-ACME-CertAutomation/dehydrated --register --accept-terms
    ```
    
    e. Run the bash script:
  	
    ```
    bash renew_certificates_for_alteon_using_ACME.sh
    ```
    
    f. Edit the crontab file to schedule the script:
  	
    ```
    crontab -e
    ```
    
    g. Add the line to run the script periodically. In the following example, the script will run every day at 00:00:

  	```
    0 0 * * * cd /etc/Alteon-ACME-CertAutomation; env https_proxy='<http://username:password@host:port>' primary_cc_password_for_ACME='<primary_cc_password_for_ACME>' secondary_cc_password_for_ACME='<secondary_cc_password_for_ACME>' sender_password_for_ACME='<sender_password_for_ACME>' /usr/bin/bash /etc/Alteon-ACME-CertAutomation/renew_certificates_for_alteon_using_ACME.sh > /var/log/Alteon-ACME-CertAutomation_last_run.log 2>&1
  	```

11.	Send an alert when the primary Cyber Controller server that holds the ACME client is unable to renew the certificates:

    a. Move / copy the **check_the_primary_cc_and_send_mail_if_needed.sh** file to the secondary Cyber Controller under the /etc/check_the_primary_cc directory.
   	
   	```
    mkdir /etc/check_the_primary_cc
    cd /etc/check_the_primary_cc
    ```
    
    b. Edit the check_the_primary_cc_and_send_mail_if_needed.sh file and modify the Cyber Controller parameters according to your setup. For example:
   	
    PRIMARY_CC_IP="10.0.0.100"
   	
    CC_USER="ACME-User"
   	
    (the password will not be writen in the file)
   	
    insecure = False
   	
   	c. Set the SENDER_EMAIL="sender_email@company.com" -- provide the sender email.
   	
    d. Set the RECIPIENT_EMAIL="recipient_email@company.com" -- provide the recipient email.
   	
    e. For additional recipients, follow the example below in the code.
   	
    f. Export the **primary_cc_password_for_ACME**, **sender_password_for_ACME**, and the **https_proxy** (optional) as environment variables to avoid setting them as plaintext in the code.:
   	
   	```
    export primary_cc_password_for_ACME='password'
    export sender_password_for_ACME='password'
    export https_proxy='http://user:password@host:port' (optional)
    ```
    
    g. Test the bash script twice, one with the correct IP address, and one time with the incorrect Cyber Controller IP address:
   	
   	```
    bash check_the_primary_cc_and_send_mail_if_needed.sh
   	```
    
    h. Change back the bash script with the correct IP address.
   	
    i. Edit the crontab file to schedule the script:
   	
   	```
    crontab -e
    ```
    
    j. Add the line to run the script periodically. The running time should be the same time as the primary Cyber Controller server runs the ACME client to renew the certificates. In the following example, the script will run every day at 00:00:
   	
   	```
    cd /etc/Alteon-ACME-CertAutomation; env https_proxy='<http://username:password@host:port>' primary_cc_password_for_ACME='<primary_cc_password_for_ACME>' sender_password_for_ACME='<sender_password_for_ACME>' /usr/bin/bash /etc/Alteon-ACME-CertAutomation/renew_certificates_for_alteon_using_ACME.sh > /var/log/check_the_primary_cc_last_run.log 2>&1
    ```
   	
## Limitation ##
When upgrading or implementing HA for Cyber Controller, ensure that you back up all ACME dehydrated files along with the cron command, and redeploy them if needed.

## Disclaimer ##
There is no warranty, expressed or implied, associated with this product. Use at your own risk.
