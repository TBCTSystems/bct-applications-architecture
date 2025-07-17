Feature Definition for 
Enterprise Certificate Management 

 

SW Lead Owner: Vitalli Poliak 

SSE: Gary Dark 

 

 

 

About This Document: 

This document presents the conceptual design, including functionality, software architecture, test strategy, and CICD strategy for a specific feature. It serves as a foundation for stakeholders and project teams to align on the feature's high-level design. 

 

Goals of this Document: 

    Enhance Readiness for Dev Team Execution: Prepare the software definition comprehensively to increase efficiency at increment planning and increment execution. 

    Stakeholder Alignment: Ensure that all key stakeholders have a unified understanding of the design and implementation strategy. 

    Facilitate Effective Communication: Serve as a reliable communication medium to development teams, conveying necessary design expectations. 

    Enhance predictability: Defining the definition and design will assist teams with having better estimations which leads to predictability for release.   

 

Guidelines for Use: 

    Maintain Appropriate Abstraction Level: Focus on high-level design aspects rather than intricate details to maintain clarity and relevance. There must be enough detail to have a clear understanding of the need and design, this can include POCs to vet out assumptions and/or find the best approach for the ‚ÄúHow‚Äù. 

    Prioritize Visuals Over Text: Use diagrams and visual representations wherever possible as they are more accessible and easier to understand than textual descriptions. 

 

Limitations of this Document: 

    Not a Complete and Comprehensive Design: This document outlines the initial direction and is not exhaustive; further detailed design and additional inputs will be required from the respective teams as execution begins. References can be added for the initial revision of Detailed design documents and ICDs. The initial direction needs to be clear and it should be as vetted as possible to avoid assumptions that may lead to unexpected work to implement the feature.  

    No Updates Post Feature Implementation Commencement: This document is not intended to be updated once the feature implementation begins. All essential information should be integrated into official design documents and controls as necessary. Teams implementing the feature need to ensure that all of their questions are addressed by this document before they begin implementation. 

 

Reviews 

This document should be reviewed by qualified representatives of all the interested stakeholders as well as teams which will be implementing this feature. The reviewers should ensure that the document is complete and correct.  If reviewing during estimation, all unresolved questions are identified, and investigations are included in the planning.  If reviewing before implementation, all questions have been resolved. 

Group 
    

Reviewer 
    

Date 

Commercial 
    

 
    

 

Software Systems 
    

 
    

 

Systems 
    

 
    

 

Embedded 
    

 
    

 

Applications 
    

 
    

 

DevOps 
    

 
    

 

‚Ä‚ÄTable of Contents 

‚Ä1	Functional Definition	3 

‚Ä1.1	Feature summary	3 

‚Ä1.2	Functional & non-functional requirements	3 

‚Ä1.3	Critical use cases and process flows	4 

‚Ä1.4	UI/UX Mockups	6 

‚Ä2	SW Design	6 

‚Ä2.1	High-level SW design	6 

‚Ä2.2	ICD additions/updates	7 

‚Ä2.3	Prototypes	7 

‚Ä3	Testing Approach	7 

‚Ä3.1	System testing	7 

‚Ä3.2	Performance testing	8 

‚Ä3.3	Interface testing	8 

‚Ä3.4	App-Device testing	8 

‚Ä3.5	Manual testing	8 

‚Ä4	CI/CD Approach	8 

‚Ä4.1	CI/CD Design	8 

‚Ä5	Work Break Down	9 

‚Ä5.1	Task break down (considering: teams, dependencies, and priority)	9 

‚Ä‚Ä 

 

 

 

 

 

 

 

 

    Functional Definition 

    Feature summary 

As cybersecurity awareness becomes more prevalent, customers increasingly require devices on their networks to be authenticated, most commonly using certificates. The existing certificate solution for Reveos 1.3 and TRAC-II devices requires manual service team intervention, which is not a scalable/feasible solution for maintaining Terumo‚Äôs globally deployed product suite. Enterprise certificate management implements mechanisms to support the automated renewal and management of certificates to authenticate the device and application communication for a customer‚Äôs system of connected Terumo devices and applications. 

 

Until customers install Lumia and Reveos Application V1.1 with embedded TOME V9.X and update Reveos devices to V2.1 certificates for Reveos 2.0 and 1.X devices will need to be managed with existing manual intervention by the service team. 

    Functional & non-functional requirements  

    Constraints 

    The solution should minimize the amount of additional hardware/infrastructure costs to the customer and TBCT. 

    The solution should minimize service involvement in certificate management for customers. 

    The solution should work on a supported protocol or framework that provides adequate flexibility and security for at least the next 5-10 years. 

    The solution should avoid resulting in statistically significant negative performance impacts to device and application communication/file transfer. 

    The solution should minimize interruptions to user (ex. blood center) operations.  

    Environment 

    The solution needs to support a restrictive network topology where devices communicate to the application, including on an isolated network, and the application is deployed on a VM/private cloud/physical server that can communicate to the internet or corporate network.  

    The solution needs to support a network topology where traffic crosses an untrusted network (the internet) to accommodate a future when Terumo applications move to the cloud.  

    The solution should consider the feasibility of supporting a topology where Terumo devices are supported on a network without an associated managing application.  

    Functional requirements 

    Managing Application 

    The managing application shall support use of the following chained certificate types of the .crt (or other) extension type:  

    Paid certificates (issued by an external Certificate Authority interfacing with the application as an intermediate Certificate Authority) 

    Self-signed certificates (issued by the application acting as internal Certificate Authority) 

    Any validity check on certificates that the managing application should perform, similar to the device? 

    The managing application shall attempt to use certificates to connect to the server when all files (local.crt, local.key, ca.crt) are present and valid. Valid is defined as: 

    Certificates are not expired 

    Certificates are labeled as client only 

    If certificates are present on the managing application but not considered valid, the managing application will log whether it is expired, an incorrect client or incorrect EKU in the application log, omitting certificate information. 

    The managing application shall log any identified certificate failures in the application log relating to application communication and file transfer. 

    The managing application shall log a connection failure due to date/time synchronization issues between the application and the server. 

    The managing application shall log a connection failure due to an incorrect secure sockets layer (SSL). The log shall indicate a failure due to an invalid certificate, expired certificate, untrusted certificate authority, or a mismatched host name. 

    The managing application shall log a connection failure due to incorrect transport layer security (TLS) configurations.    

    The managing application shall terminate connection attempts made by devices with certificates that cannot be authenticated.  

    The managing application shall allow for installation of certificates by the certificate management service. 

    The managing application shall request certificates from the Certificate Authority for each end point. 

    The managing application shall allow for certificates to be updated by the certificate management service. 

    The managing application shall provide the ability to turn the certificate authority provisioning server on or off. 

    The managing application shall provide the ability to enter a whitelist of device IP addresses (this may need to state unique device identifier) on the certificate authority provisioning server. 

    The managing application shall allow for the removal of certificates by the certificate management service. 

    The managing application shall provide an indication for the following certificate states:  

    Expiring within x time period 

    Expired/Invalid ‚Äì may tie into connectivity indications as this means devices will not be able to connect with the managing application.   

    Step-ca Certificate Authority Solution 

    The step-ca Certificate Authority shall issue root certificates of the .crt certificate type to the client from the following sources: 

    Paid root certificates (issued by an external CA interfacing with the certificate management service as an intermediate CA) 

    Self-signed root certificates (issued by the customer with the certificate management service as an intermediate CA) 

    Root certificate issued by the step-ca Certificate Authority solution. 

    The certificate authority solution provisioning service shall allow specific IP addresses to be whitelisted. Only the whitelisted IP addresses will be allowed to request a root certificate. 

    The certificate authority solution provisioning service shall issue a local.key and local.crt to any whitelisted IP address that requests it. 

    The certificate authority provisioning service shall be configurable on or off. 

    The certificate authority shall support a configurable auto shut off timer. 

    When configured off the provisioning service shall clear whitelists. 

    The certificate management service shall provide the ability to issue certificates. 

    The certificate management service shall monitor the status of issued certificates for:  

    External CA revocation (if internet connected and using paid certificates)    

    The certificate management service shall provide an automated mechanism for renewing certificates.  

    When a certificate renewal is requested, the certificate management service shall provide the updated certificate to the device using that issued certificate only if the client has a valid root certificate.  

    The certificate authority shall terminate connection attempts made by a managing application with certificates that cannot be authenticated. 

    When interfaced with an external certificate authority, the certificate management service shall provide an automated mechanism for certificate revocation.  

    The certificate management service shall provide a manual mechanism for triggering certificate revocation.  

    The certificate management service shall provide a manual mechanism for triggering certificate revocation. 

    Non-functional requirements 

    Backwards compatibility non-functional requirements 

    Device 

    N/A 

    Managing Application 

    The application shall support a mixed fleet of devices at the following versions: 1.3, 1.4, 2.0, 2.1, etc‚Ä¶. (Need a compatibility matrix for devices and applications when this gets implemented on specific platforms.) 

    For devices at versions x and newer, the managing application shall require successful certificate authentication for connection.  

    Upgrade/Downgrade compatibility non-functional requirements 

    Device 

    For the following upgrade/downgrade paths, the device shall persist valid certificates: List to/from versions  

    Managing Application 

    For the following upgrade/downgrade paths, the application shall persist valid certificates: List to/from versions 

    Cybersecurity non-functional requirements 

    Are there special cases here where we would want to consider forcing the reissuance of certificates? 

    Performance requirements 

    Critical use cases and process flows 

    Use Case DiagramPicture 151316481, Picture 

    UC-01 ‚Äì New customer installation  

    New devices and new application are installed at a customer site and certificates must be issued and somehow provided to devices (and application server) that have not yet authenticated with the application.  

 
    

Detailed Description 

Primary Actor 
    

Service Engineer 

Pre-Conditions 
    

The device and servers and install and configured and without valid certificates. 

Main flow 
    

    The service engineer sets the provisioning server to on. 

    The application server connects to the provisioning server and asks for the provisioning certificates. 

    The provisioning server verifies the existence of the application server using the ACME protocol. 

    The provisioning server issues provisioning certificates to the application server. 

    The application uses the provisioning certificate to connect to the Certificate Management server, and requests a root certificate. 

    The Certificate Authority issues certificate to device and application app 

    Device and application server install the certificates. 

    Device connects to Application Server and authenticate each other using the newly issued certificates. 

    The service engineer sets the provisioning server off. 

Post-Conditions 
    

Device is connected to Application Server using certificates for authentication 

 

    UC-02 ‚Äì Add a device to an existing customer installation  

    A new device that has not yet authenticated with the application is installed at an existing customer site that has other devices and the application already set up and being used with authentication.  

 
    

Detailed Description 

Primary Actor 
    

Service Engineer 

Pre-Conditions 
    

The device and servers are installed and configured without valid certificates. 

Main flow 
    

    The service engineer sets the provisioning server to on. 

    On power up, the device connects to the provisioning server and asks for the provisioning certificates. 

    The server verifies the existence of the device using ACME protocol. 

    Then the server issues a provisioning certificate to the device. 

    Device uses the provisioning certificate to connect the Certificate Management server, and request for a set of certificates. 

    The Certificate Authority issues certificate to device. 

    Device installs the certificates and uses them to connect to Application Server 

    The service engineer sets the provisioning server to off. 

Post-Conditions 
    

Device is connected to Application Server using certificates for authentication 

 

    UC-03 ‚Äì Offline device reconnects to application 

    A device that was previously authenticated with the application was taken offline for servicing and is being returned to production use but may have an expired or revoked certificate.  

 
    

Detailed Description 

Primary Actor 
    

Service Engineer 

Pre-Conditions 
    

The device has expired or revoked certificate 

Main flow 
    

    Device is powered up. 

    Device invalidates the existing certificate. 

    The device then connects to the Certificate Management Server and asks for a new set of certificates. 

    The Certificate Management server issues certificate to device 

    Device installs the certificates and uses them to connect to Application Server  

Post-Conditions 
    

Device is connected to Application Server using certificates for authentication 

 

    UC-04 ‚Äì Certificates being used by application and devices are revoked by external CA 

    Based on information provided by the external CA, the system reissues certificates to application server and devices somehow.  

This flow is similar to UC-03 

    UC-05 ‚Äì Certificates being used by application and devices are revoked by internal/intermediate CA 

    The customer requires revocation of certificates used by their system and needs to reissue certificates to the application server and devices somehow.  

 
    

Detailed Description 

Primary Actor 
    

Service Engineer/Customer 

Pre-Conditions 
    

The root or intermediate root used by Certificate Management server is expired or revoked certificate. 

Main flow 
    

    The service engineer/customer acquires new root certificate for Certificate Management Server 

    The service engineer/customer installs the certificates to Certificate Management Server 

    Service engineer or customer restarts Certificate Management Server, Application Server and Devices. 

    Applicate server and Devices invalidate the old certificate and acquire new certificates similar to UC-03. 

Post-Conditions 
    

Device is connected to Application Server using certificates for authentication 

 

    UC-06 ‚Äì Certificates being used by the application and devices are nearing expiry and must be renewed by the system.  

 

    Certificates being used by the application server and devices are nearing expiration and need to be renewed without interruption to daily operations.  

Expired certificates are allowed to be renewed. This is no longer a 	valid use-case. 

 

    SW Design 

    Picture 1895593301, Picture 

Figure 1. Block Diagram 

Picture 206826587, Picture 

Figure 2 Web page for Provisioning server 

 

Picture 644042803, Picture 

 

Figure 3 Provisioning Sequence Diagram 

 

    High-level SW design 

Figure 1 above shows the components that make the Certificate Managed environment, with device and Application Server being clients to Smallstep Certificate management, and the provisioning Web App. 

    SmallStep step-ca 

This is the Certificate Server. It has two components: a provisioning server and a certificate manager server. 

    Provisioning Server ‚Äì this server issues certificates to clients, in which certificates are used as bootstrapping certificates. The certificate issued has a long expiration date. The initial certificate is used for authentication to the Certificate Manager. This server is intended to be in service during the provisioning phase. This is typically during installation or when a new device is added to the system. 

    Certificate Manager ‚Äì this server issues certificates to clients used for authentication: server authenticating the client and client authenticating the server. 

 

    Provisioning Web App 

This component exposes the ability for the Provisioning Server to be turned on or off. The Web App is part of the Application Server, e.g. Lumia,  

    Device 

The device has ACME client component, step client component, Communications component and the trust store. 

    ACME client  

It is responsible for getting the provisioning certificate. This client adheres to the ACME protocol using http-01 challenge, where the device provides REST-API or a given URL for the Provisioning server to validate the content. 

    Step client 

Using the provisioned certificate for authentication, the Step client is responsible for getting the certificate used for authenticating the app/device (e.g. Lumia/Reveo) communications. 

    MQTT/REST API client 

This is the communication client where TLS is utilized to protect the channel, and where the certificate obtained by Step client is used. 

    Trust Store 

This is the component in the device that manages the certificates. 

    Application Server 

This is the application server for the device, e.g. Lumia/Kinari.  

 

    Device Component Design 

    Step client/ACME client 

This component will use the step client, an implementation by Smallstep. The source code will be taken from https://github.com/smallstep/cli. The code will be compiled as part of the common OS build. 

    Client Wrapper. 

Picture 1637449589, Picture 

Access to the step client from the c++ application will be made available via a 	class wrapper or facade. The wrapper will expose the basic functionalities through 	a well-defined interface: 

 

Method 
    

Responsibility 

provision 
    

connects to the Provisioning server and requests for initial certificate using ACME protocol. 

getCertificate 
    

Connects to the Certificate Manager using the certificate acquired by provision method for authentication 

renewCertificate 
    

Connects to the Certificate Manager and renew the existing certificate 

validateCertificate 
    

Validates a given set of certificates 

 
    

 

    Certificate Use Workflow 

The diagram below shows the flow of work by the device given a varying set of conditions. 

This flow will be implemented using the ActivityStep in Common libraries. ActivityStep work items will use the StepWrapper. 

APicture 764926102, Picture 

 

    Device Configuration for Certificate Mangement 

Access to Provisioning Server and Certificate Manager will both be configured as a set of URL and port combination. This configuration items will be exposed by NetworkInfo.xml 

 

    ICD additions/updates 

    Provisioning Server ‚Äì Provisioning Client  

This uses ACME protocol defined by ACME provisioning type in step-ca. No additional ICD is required. 

 

    Certificate Manager ‚Äì Device step client 

This uses the x509 type of provisioner in step-ca. No additional ICD is needed. 

 

    Prototypes 

<List link of repo-branch where any ‚Äústeel-thread‚Äù prototypes to reduce implementation risk have been worked on> 

 

    Testing Approach 

    Test Architecture 

    Setup ACM environment for Pytest Framework 

    Scripts and cnfs for generation of TLS self-signed certificates 

    Device 

    Unit tests for implementation of stepci methods in section 2 above. 

    Manual interface test for provision() and getCertifcate() workflow. 

    Using paid 

    Using self-signed 

    Verification of successful cert install by ACM 

    Verification of successful cert removal by ACM 

    Unit tests for certificate validity 

    Files present 

    Expiration satisfied 

    Client only/EKU settings 

    Automated test for log inspection of invalid certificates 

    Automated test for log inspection of device communication failures and file transfers from the certificate application. 

    Manual test for certificate renewal 

    Paid 

    Self-signed 

    Placeholder for connection to app when certs are present 

    Manual test for device refusing connection to unauthenticated managing application ‚Äì FLAG mismatch between req‚Äôt and suggested dev design 

    Follow on for device requesting updated certificates from ACM application, and reattempting connection 

    Automated test to inspect expiry window report of installed certificates 

    Automated test to inspect expired certificate status 

    Automated test to inspect invalid certificate status 

 

    CI/CD Approach 

    CI/CD Design 

<Describe any additions/updates to the CICD pipeline for individual subsystems and integration environments> 

 

 

 

    Work Break Down Structure 

    Task break down  

    Device 

    Integrate step/cli in build 

    Implement StepWrapper 

    Implement ActivityStep workflow 

    Busy Indicator 

    Alarm Condition 

    Multi-threading process with StepWrapper 

    Integrate the new ActivityStep with ConfigCheck flow 

 {
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
  }
