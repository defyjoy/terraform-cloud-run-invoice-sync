
### Why granting Editor is the wrong response, and its blast radius.
- Granting EDITOR is wrong as it has approx over 4000 permissions adding permission to a role or a individual IAM user is overly permissive approach and can be threatening in compromised security incidents.
- The blast radius can be any services which has CRUD operations in it. Secrets manager with secure information may leak
- Exposure of data in databases , access keys ( if any ) and other access to services might be compromised and hence now it's considered as a legacy role. 

### Why a JSON key is the wrong CI pattern, and what WIF solves.
- Json key is permanent without expiry. Hence anybody with compromised key can gain access to GCP and have illegal access to data and GCP resources.
- Credentials arent tied to the repository , branch  or my orkflow or deployment environment. Its straight having access to the GCP systems.
- Needs to be stored externally in github secrets
- Limited external identity conditional authentication limitations 

What OIDC and WIF solves - 
- Shortlived credentials using OIDC token and in exchange of oidc token we get federated token to access the services via the service accounts.
- Can authenticate external identity through claims and tokens . 
- Federation is much easier through the OIDC tokens and authentication through the github and GCP apis. 
- Tied to claims like repository ,branch , workflow , identity owner etc.
- Verification against trusted provider , in case of github and gcp both are on trusted party for each other to provide the oidc token and verify happens on both sides.
- Why it matters becuase we can authenticate using service accounts with short lived token on GCP identity side and a machine-to-machine communication.

### Ranked root-cause hypotheses for the secret permission error, with the gcloud commands you would run first.
- Wrong servicve account and service account permissions
- Secret accessor principal incorrectly configured
- Secret version mismatched across the accessor

I would run these commands to identify in the order - 

```
# 1. What identity is Cloud Run ACTUALLY running as?
gcloud run services describe invoice-sync --project=yeti-504903 --region=us-central1 --format="value(spec.template.spec.serviceAccountName)"

# 2. What secrets is Cloud Run ACTUALLY configured to use?
gcloud run services describe invoice-sync --project=yeti-504903 --region=us-central1 --format=yaml

# 3. Does that runtime identity have IAM on THIS secret?
gcloud secrets get-iam-policy db-password --project=yeti-504903 --format=yaml

# 4. Does the referenced version actually exist and remain enabled?
gcloud secrets versions list db-password --project=yeti-504903
```


### The IAM model — who deploys, who reads the secret, who runs the Job — and the risk if an engineer’s laptop is compromised.
Its an identity and permission split operation - 

- The IAM models has few actors -
   - Engineer ( human actor )
   - github-deployer - ( machine user/service account with WIF) - Runs the job and authenticates the github actions job with oidc
   - Cloud run ( service account ) - This reads the secrets in the container env variable

### Your VPC connector choice — what it protects, what it does not, and what you would add next for a real PHI path.
- What VPC connector protects is the cloud run instance and its not publicly open via cloud run default dns url 

- What it doesn't protect is the data , network path is not data compliance boundary. The data protection path is more of a shared model than purely infra model from cloud networking. VPC connector doesnt protect the data compliance boundary.

What I want to add - 
- If the api is accessed by frontend I would probably keep it totally ILB level and let frontend BFF ( backend for frontend ) access the backend through GCP network backbone via vpc connector and internal load balancer.
- Adding cloud armour in front of cloud run.
- Adding certificates to load balancer 
- Adding authentication and dedicated cloud service account ( already exists )
- Logging an identifying as PHI compliance boundary and identification of threats.


### HIPAA / regulated-data posture — what you would refuse, log, or isolate differently if this secret were PHI-adjacent.
- DO NOT LOG - patient details , phone numbers , credit cards for payments , clinical data passwords etc .
- We can log - API status codes, traces etc. 
- Refuse the secret accessor for developers service accounts or developers user accounts 
- Give cloud run service account to secretmanager.secretAccessor permission only for service-to-machine communication.

### What you would resolve independently versus escalate to the Cloud Lead, with a recommendation rather than an open question.
What I would solve by myself - 
- Resolve architectural structural connectivity problems . 
- Network resolution and private access setup
- VPN setup if needed 
- Internal IAM related permissions identifying the principal + permission + which resource .
- Fix networking firewalls with least priviledge and targeted network path.


What I would escalate to cloud lead - 
- A organizational policy causing deny effect on service account permission 
- Refuse and escalate any permission requirements across organization to individual users
- Adding broader permission role ( with a recommedation with a custom role instead)


In short If I can determine the root cause I can investigate independently without touching organizational policies , I would resolve it myself . 
If the security architecture is getting denied , broken and with research its found its breaking fundamental security and organizational policies.  IT should be escalated, discussed with a recommendation.

### Time spent and anything intentionally skipped.
- I tried to apply conditional targeted IAM conditions to an extent for github-deployer. But it was quite a bit of task for a single service.
Instead I chose to target a single branch for the github deployer 
- Skipped DNS setup and mapping the load balancer to DNS records


### Links: repository, successful Actions run, alert delivery evidence.


https://github.com/defyjoy/terraform-cloud-run-invoice-sync/actions/runs/32228072166
