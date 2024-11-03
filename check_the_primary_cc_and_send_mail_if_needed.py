import requests
from requests.auth import HTTPBasicAuth
from time import sleep
import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import urllib3


sender_email = "sender_email@company.com"
recipient_email = "recipient_email@company.com"


# Suppress the InsecureRequestWarning
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def check_primary_cc_availability():
    # Variables
    primary_cc_ip_port = '10.0.0.100:2189'
    cc_user = 'root'
    cc_password = os.environ.get('primary_cc_password_for_ACME')
    # Set insecure to True if the Cyber Controller certificate is self-signed.
    insecure = True

    # URL construction
    url = f'https://{primary_cc_ip_port}/api/adc'

    # Headers
    headers = {
        'accept': 'application/json, text/plain, */*',
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                      ' (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
    }

    # Attempt to send request up to 3 times
    for attempt in range(3):
        try:
            response = requests.get(url, headers=headers, verify=not insecure, auth=HTTPBasicAuth(cc_user, cc_password))
            if response.status_code == 200:
                print(f"Attempt {attempt + 1}: Success")
                return 200
            elif attempt < 2:  # Only wait if there will be another attempt
                print(f"Attempt {attempt + 1}: Failed with status code {response.status_code}")
                print("Trying again in 10 seconds...")
                sleep(10)
            else:
                print(f"Attempt {attempt + 1}: Failed with status code {response.status_code}")
        except requests.exceptions.ConnectionError as e:
            print(f"Attempt {attempt + 1}: Connection error. Server is down or unreachable. Error: {str(e)}")
            if attempt < 2:
                print("Trying again in 10 seconds...")
                sleep(10)
            else:
                return "Server Unreachable"

    return "Failed after 3 attempts"


def send_mail(subject, body):
    print("Sending an email...")
    sender_password = os.environ.get('sender_password_for_ACME')
    to_addrs = recipient_email.split(";")

    message = MIMEMultipart("alternative")
    message["Subject"] = subject
    message["From"] = sender_email
    message["To"] = recipient_email

    # - Optional - add CC recipients in case of errors
    # if subject != "Cyber Controller successfully renewed the certificates.":
    #    print("Adding a cc recipient")

    #   # Add CC recipients
    #    message["Cc"] = 'additional_recipient1@comapny.com; additional_recipient2@comapny.com'
    #    to_addrs.append("additional_recipient1@comapny.com")
    #    to_addrs.append("additional_recipient2@comapny.com")

    html_body = MIMEText(body, "html")
    message.attach(html_body)

    mailserver = smtplib.SMTP(host='smtp.office365.com', port=587)
    mailserver.ehlo()
    mailserver.starttls()
    mailserver.ehlo()
    mailserver.login(sender_email, sender_password)
    mailserver.sendmail(from_addr=sender_email, to_addrs=to_addrs, msg=message.as_string())
    mailserver.quit()


if __name__ == "__main__":
    primary_cc_status = check_primary_cc_availability()
    print("primary_cc_status is", primary_cc_status)
    if primary_cc_status != 200:
        send_mail("Cyber Controller Error: Certificate Renewal Issue",
                  "It appears that the Cyber Controller managing the ACME "
                  "client is down and unable to renew the Alteon certificates.\
                  <br>This message was sent from the secondary Cyber Controller.")
    else:
        print("Primary Cyber Controller is available")

