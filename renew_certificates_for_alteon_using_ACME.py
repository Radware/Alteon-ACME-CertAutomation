import json
import os
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import subprocess

sender_email = "sender_email@company.com"
recipient_email = "recepient_email@company.com"


# This recipient will receive the email summary about the renewal.
# Multiple recipients can be included by separating their email addresses with a semicolon (';').
# Example for multiple recipients
# receiver_email = "recipient1_email@company.com;recipient1_email@company.com"


def prepare_certs_status_file(alteon_devices_per_domains):
    # Get the current directory
    current_dir = os.path.dirname(os.path.abspath(__file__))

    # Define the output file path
    output_file = os.path.join(current_dir, 'certs_status.json')

    # Initialize an empty dictionary to hold the domains
    domains = {}

    # Process each domains.txt file
    for domains_file in alteon_devices_per_domains.keys():
        input_file = os.path.join(current_dir, domains_file)
        with open(input_file, 'r') as file:
            for line in file:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                # Remove content after '>' because that is alias and not a domain
                line = line.split('>')[0].strip()
                # Split the line into domains and add them to the dictionary
                for domain in line.split():
                    domains[domain] = ""

    # Write the domains to the output JSON file
    with open(output_file, 'w') as file:
        json.dump(domains, file, indent=2)


def load_certs_status(file_path):
    with open(file_path, 'r') as file:
        return json.load(file)


def create_html_table(certs_status):
    table_html = """
    <table border="1">
        <tr>
            <th>Domain</th>
            <th>Status</th>
        </tr>
    """
    for domain, status in certs_status.items():
        if status == "":
            status = "Failed"
        if "Success" in status:
            color = "green"
        elif "Unchanged" in status:
            color = "black"
        else:
            color = "red"
        table_html += f"""
        <tr>
            <td>{domain}</td>
            <td style="color: {color};">{status}</td>
        </tr>
        """
    table_html += """
    </table>
    <p>For more information, please view the following logs:
    <br>
    <br>Cyber Controller CLI (root) - <b>/var/log/Alteon-ACME-CertAutomation_last_run.log</b> - describes the ACME flow.
    <br>Cyber Controller GUI - <b>&lt;cyber-controller-address:2189&gt/ui/#/app/administration/serverLogs</b> -
    describes the flow of deploying certificates on the ADCs.</p>
    """
    return table_html


def determine_subject(certs_status):
    statuses = set(certs_status.values())
    if all("Unchanged" in status for status in statuses):
        return "All certificates are unchanged."
    elif all("Success" in status or "Unchanged" in status for status in statuses):
        return "Cyber Controller successfully renewed the certificates."
    else:
        return "There is a failure while renewing the certificates."


def send_mail(subject, body):
    print("Sending an email...")

    sender_password = os.environ.get('sender_password_for_ACME')
    # For manual running run "export sender_password_for_ACME=<SENDER_PASSWORD>"
    # For scheduling using crontab, add "env export sender_password_for_ACME=<SENDER_PASSWORD> /usr/bin/python3.8 ..."

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
    current_dir = os.path.dirname(os.path.abspath(__file__))
    certs_status_file = os.path.join(current_dir, "certs_status.json")
    dehydrated_file = os.path.join(current_dir, "dehydrated")

    # Load alteon_devices_per_domains from JSON file
    with open(os.path.join(current_dir, 'alteon_devices_per_domains.json'), 'r') as file:
        alteon_devices_per_domains = json.load(file)

    prepare_certs_status_file(alteon_devices_per_domains)

    # Run the dehydrated
    for domains_file, alteon_devices in alteon_devices_per_domains.items():
        command = f"export ALTEON_DEVICES={alteon_devices} && bash {dehydrated_file} -c -g --domains-txt {domains_file}"
        process = subprocess.Popen(command, shell=True)
        process.wait()  # Wait for the current process to finish before starting the next one

    # Load certificate status
    certs_status = load_certs_status(certs_status_file)

    # Determine email subject and create HTML table
    subject = determine_subject(certs_status)
    html_table = create_html_table(certs_status)

    # Send email
    send_mail(subject, html_table)
