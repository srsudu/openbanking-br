#/bin/bash

#
# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Credentials settings helper function
to_eval=""
function set_cred(){
    to_eval=$1
    local suffix=$2
    local apigee_user_cred="-u $APIGEE_USER -p $APIGEE_PASSWORD -o $APIGEE_ORG -e $APIGEE_ENV"
    local apigee_token_cred="-t $APIGEE_TOKEN -o $APIGEE_ORG -e $APIGEE_ENV"
    if [[ -z "${APIGEE_TOKEN}" ]]; then
        to_eval="${to_eval} ${apigee_user_cred}"
    else
        to_eval="${to_eval} ${apigee_token_cred}"
    fi
    to_eval="${to_eval} ${suffix}"
    eval "$to_eval"
}

# Credentials settings helper function for org level config
function set_cred_org(){
    to_eval=$1
    local suffix=$2
    local apigee_user_cred="-u $APIGEE_USER -p $APIGEE_PASSWORD -o $APIGEE_ORG"
    local apigee_token_cred="-t $APIGEE_TOKEN -o $APIGEE_ORG"
    if [[ -z "${APIGEE_TOKEN}" ]]; then
        to_eval="${to_eval} ${apigee_user_cred}"
    else
        to_eval="${to_eval} ${apigee_token_cred}"
    fi
    to_eval="${to_eval} ${suffix}"
    eval "$to_eval"
}

#### Utility functions
function replace_with_jwks_uri {
 POLICY_FILE=$1
 JWKS_PATH_SUFFIX=$2
 POLICY_BEFORE_JWKS_ELEM=$(sed  '/<JWKS/,$d' $POLICY_FILE)
 POLICY_AFTER_JWKS_ELEM=$(sed  '1,/<JWKS/d' $POLICY_FILE)
 echo $POLICY_BEFORE_JWKS_ELEM'<JWKS uri="https://'$APIGEE_ORG-$APIGEE_ENV'.apigee.net'$JWKS_PATH_SUFFIX'" />'$POLICY_AFTER_JWKS_ELEM > temp.xml
 # The following step is for pretty printing the resulting edited xml, we don't care if it fails. If failed, just use the original file
 xmllint --format temp.xml 1> temp2.xml 2> /dev/null
 if [ $? -eq 0 ]; then
    cp temp2.xml $POLICY_FILE
 else
    cp temp.xml $POLICY_FILE
 fi
 rm temp.xml temp2.xml 
}
# This function generates RSA Private/public key pair, and the corresponding JWKS file
function generate_private_public_key_pair {
   KEY_PAIR_NAME=$1
   KEY_PAIR_FRIENDLY_NAME=$2
   # Generate RSA Private/public key pair
   echo "--->"  "Generating RSA Private/public key pair for "$KEY_PAIR_FRIENDLY_NAME"..."
   
   OUT_FILE=$KEY_PAIR_NAME"_rsa_private.pem"
   openssl genpkey -algorithm RSA -out $OUT_FILE -pkeyopt rsa_keygen_bits:2048
   IN_FILE=$OUT_FILE
   OUT_FILE=$KEY_PAIR_NAME"_rsa_public.pem"
   openssl rsa -in $IN_FILE -pubout -out $OUT_FILE
   echo "Private/public key pair generated and stored in ./setup/certs. Please keep private key safe"
   echo "----"
   # Generate jwk format for public key (and store it in a file too) - Add missing attributes in jwk generated by command line
   IN_FILE=$OUT_FILE
   APP_JWK=$(pem-jwk $IN_FILE  | jq '{"keys": [. + { "kid": "PlaceHolderKid" } + { "use": "sig" }]}')  
   echo $APP_JWK > $KEY_PAIR_NAME.jwks
   sed  -i '' "s/PlaceHolderKid/$KEY_PAIR_NAME/" $KEY_PAIR_NAME.jwks
}

# Create Caches and dynamic KVM used by oidc proxy
echo "--->"  Creating cache OIDCState...
set_cred "apigeetool createcache" "-z OIDCState --description \"Holds state during authorization_code flow\" --cacheExpiryInSecs 600"
echo "--->"  Creating cache PushedAuthReqs...
set_cred "apigeetool createcache" "-z PushedAuthReqs --description \"Holds Pushed Authorisation Requests during authorization_code_flow\" --cacheExpiryInSecs 600"
# echo "--->"  Creating dynamic KVM PPIDs...
# apigeetool createKVMmap -u $APIGEE_USER -p $APIGEE_PASSWORD -o $APIGEE_ORG -e $APIGEE_ENV --mapName PPIDs --encrypted
echo "--->"  Creating dynamic KVM TokensIssuedForConsent...
set_cred "apigeetool createKVMmap" "--mapName TokensIssuedForConsent --encrypted"
# Create KVM that will hold consent information
echo "--->"  Creating dynamic KVM Consents...
set_cred "apigeetool createKVMmap" "--mapName Consents --encrypted"
# Create cache that will hold consent state (Used by basic consent management proxy)
echo "--->"  Creating cache ConsentState...
set_cred "apigeetool createcache" "-z ConsentState --description \"Holds state during consent flow\" --cacheExpiryInSecs 600"

# Create cache that will hold consent state (Used by basic consent management proxy)
echo "--->"  Creating cache ConsentState...
set_cred "apigeetool createcache" "-z ConsentState --description \"Holds state during consent flow\" --cacheExpiryInSecs 600"


# KVM mockOBBRClient

 # Deploy Shared flows
cd src/shared-flows
for sf in $(ls .) 
do 
    echo "--->"  Deploying $sf Shared Flow 
    cd $sf
    set_cred "apigeetool deploySharedflow" "-n $sf"
    cd ..
done

 # Deploy banking apiproxies
cd ../apiproxies/banking
for ap in $(ls .) 
do 
    echo "--->"  Deploying $ap Apiproxy
    cd $ap
    set_cred "apigeetool deployproxy" "-n $ap"
    cd ..
done

 # Deploy Common Proxies
cd ../common
for ap in $(ls .) 
do 
    echo "--->"  Deploying $ap Apiproxy
    cd $ap
    set_cred "apigeetool deployproxy" "-n $ap"
    cd ..
done

# Deploy Admin Proxies
cd ../admin/OBBR-Admin
echo "--->"  Deploying OBBR-Admin Apiproxy
set_cred "apigeetool deployproxy" "-n OBBR-Admin"
cd ..

# Deploy utils Proxies
cd ../utils/mock-obbr-client
echo "--->"  Deploying mock-obbr-client Apiproxy
set_cred "apigeetool deployproxy" "-n mock-obbr-client"
cd ..

# Deploy authnz related Proxies
cd ../authnz
for ap in $(ls .) 
do 
    echo "--->"  Deploying $ap Apiproxy
    cd $ap
    set_cred "apigeetool deployproxy" "-n $ap"
    cd ..
done
cd ../../../
# Create products

echo "--->"  Creating API Product: "Accounts"
set_cred_org "apigeetool createProduct" "--productName \"OBBRAccounts\" --displayName \"Accounts\" --approvalType \"auto\" --productDesc \"Get access to Accounts APIs\" --proxies OBBR-Accounts --scopes \"bank:accounts.basic:read,bank:accounts.detail:read\" -environments $APIGEE_ENV"

#echo "--->"  Creating API Product: "Transactions"
#set_cred_org "apigeetool createProduct" "--productName \"OBBRTransactions\" --displayName \"Transactions\" --approvalType \"auto\" --productDesc \"Get access to Transactions APIs\" --proxies OBBR-Transactions --scopes \"bank:transactions:read\" -environments $APIGEE_ENV" 

echo "--->"  Creating API Product: "OIDC"
set_cred_org "apigeetool createProduct" "--productName \"OBBROIDC\" --displayName \"OIDC\" --approvalType \"auto\" --productDesc \"Get access to authentication and authorisation requests\" --proxies oidc --scopes \"openid, profile\" -environments $APIGEE_ENV"

# Create product for Consents
echo "--->"  Creating API Product: "Consents"
set_cred_org "apigeetool createProduct" "--productName \"OBBRConsents\" --displayName \"Consents\" --approvalType \"auto\" --productDesc \"Manage Consents\" --proxies OBBR-Consent --scopes \"consents\" -environments $APIGEE_ENV"

# Create product for Resources
echo "--->"  Creating API Product: "Resources"
set_cred_org "apigeetool createProduct" "--productName \"OBBRResources\" --displayName \"Resources\" --approvalType \"auto\" --productDesc \"Get access to Resources APIs\" --proxies OBBR-Resources --scopes \"resources\" -environments $APIGEE_ENV"

# Create product for dynamic client registration
#echo "--->"  Creating API Product: "DynamicClientRegistration"
#set_cred_org "apigeetool createProduct" "--productName \"OBBRDynamicClientRegistration\" --displayName \"DynamicClientRegistration\" --approvalType \"auto\" --productDesc \"Dynamically register a client\" --proxies OBBR-DynamicClientRegistration --scopes \"cdr:registration\" -environments $APIGEE_ENV"

# Create product for Admin
echo "--->"  Creating API Product: "Admin"
set_cred_org "apigeetool createProduct" "--productName \"OBBRAdmin\" --displayName \"Admin\" --approvalType \"auto\" --productDesc \"Get access to Admin APIs\" --proxies OBBR-Admin --scopes \"admin:metadata:update,admin:metrics.basic:read\" -environments $APIGEE_ENV"


# Create Dev

# Create a test developer who will own the test app
# If no developer name has been set, use a default
if [ -z "$OBBR_TEST_DEVELOPER_EMAIL" ]; then  OBBR_TEST_DEVELOPER_EMAIL=OBBR-Test-Developer@somefictitioustestcompany.com; fi;
echo "--->"  Creating Test Developer: $OBBR_TEST_DEVELOPER_EMAIL
set_cred_org "apigeetool createDeveloper" "--email $OBBR_TEST_DEVELOPER_EMAIL --firstName \"OBBR Test\" --lastName \"Developer\"  --userName $OBBR_TEST_DEVELOPER_EMAIL"


# Create app

# Create a test app - Store the client key and secret
echo "--->"  Creating Test App: OOBRTestApp...

APP_CREDENTIALS=$(set_cred_org "apigeetool createApp" "--name OBBRTestApp --apiProducts \"OBBRAccounts,OBBROIDC\" --email $OBBR_TEST_DEVELOPER_EMAIL --json | jq .credentials[0]")
APP_KEY=$(echo $APP_CREDENTIALS | jq -r .consumerKey)
APP_SECRET=$(echo $APP_CREDENTIALS | jq -r .consumerSecret)

# Update app attributes
REG_INFO=$(sed -e "s/dummyorgname/$APIGEE_ORG/g" -e "s/dummyenvname/$APIGEE_ENV/g" ./setup/baseRegistrationInfoForOBBRTestApp.json)
REQ_BODY='{ "callbackUrl": "https://httpbin.org/post", "attributes": [ { "name": "DisplayName", "value": "OBBRTestApp" }, { "name": "SectorIdentifier", "value": "httpbin.org" },'
echo $REQ_BODY $REG_INFO "]}" >> ./tmpReqBody.json
curl https://api.enterprise.apigee.com/v1/organizations/$APIGEE_ORG/developers/$OBBR_TEST_DEVELOPER_EMAIL/apps/OBBRTestApp \
  -H "Authorization: Bearer $APIGEE_TOKEN" \
  -H 'Accept: */*' \
  -H 'Content-Type: application/json' \
  -d @./tmpReqBody.json
rm ./tmpReqBody.json

echo \n.. App created. When testing admin APIs use the following client_id: $APP_KEY

mkdir setup/certs
cd setup/certs

# Generate RSA Private/public key pair for client app:
generate_private_public_key_pair OBBRTestApp "Test App"

# Generate a public certificate based on the private key just generated
echo "--->"  "Generating a public certificate for Test App..."
openssl req -new -key OBBRTestApp_rsa_private.pem -out OBBRTestApp.csr -subj "/CN=OBBR-TestApp" -outform PEM
openssl x509 -req -days 365 -in OBBRTestApp.csr -signkey OBBRTestApp_rsa_private.pem -out OBBRTestApp.crt
echo Certificate OBBRTestApp.crt generated and stored in ./setup/certs. You will need this certificate and private key when/if enabling mTLS and HoK verification

# Generate RSA Private/public key pair for the mock OBBR Register:
generate_private_public_key_pair MockOBBRRegister "Mock OBBR Register"
echo "Use private key when signing JWT tokens used for authentication in Admin API Endpoints"
echo "----"

# Generate RSA Private/public key pair to be used by Apigee when signing JWT ID Tokens
generate_private_public_key_pair OBBRRefImpl "OBBR Reference Implementation to be used when signing JWT Tokens"

# Create a new entry in the OIDC provider client configuration for Apigee,
# so that it is recognised by the OIDC provider as a client
echo "--->"  "Creating new entry in OIDC Provider configuration for Apigee"
# Generate a random key and secret
OBBRREFIMPL_OIDC_CLIENT_ID=$(openssl rand -hex 16)
OBBRREFIMPL_OIDC_CLIENT_SECRET=$(openssl rand -hex 16)
OBBRREFIMPL_JWKS=`cat ./OBBRRefImpl.jwks`
APIGEE_CLIENT_ENTRY=$(echo '[{ "client_id": "'$OBBRREFIMPL_OIDC_CLIENT_ID'", "client_secret": "'$OBBRREFIMPL_OIDC_CLIENT_SECRET'", "redirect_uris": ["https://'$APIGEE_ORG'-'$APIGEE_ENV'.apigee.net/authorise-cb"], "response_modes": ["form_post"], "response_types": ["code id_token"], "grant_types": ["authorization_code", "client_credentials","refresh_token","implicit"], "token_endpoint_auth_method": "client_secret_basic","jwks": '$OBBRREFIMPL_JWKS'}]')
OIDC_CLIENT_CONFIG=$(<../../src/apiproxies/authnz/oidc-mock-provider/apiproxy/resources/hosted/support/clients.json)
echo $APIGEE_CLIENT_ENTRY > ../../src/apiproxies/authnz/oidc-mock-provider/apiproxy/resources/hosted/support/clients.json
echo "----"

# Create KVMs that will hold the JWKS and private Key for both the mock OBBR register, and the mock adr client
# echo "--->"  Creating KVM mockOBBRRegister...
# set_cred "apigeetool createKVMmap" "--mapName mockOBBRRegister --encrypted"
# echo "--->"  Adding entries to mockOBBRRegister...
# MOCKREGISTER_JWK=`cat ./MockOBBRRegister.jwks`
# MOCKREGISTER_PRIVATE_KEY=`cat ./MockOBBRRegister_rsa_private.pem`
# set_cred "apigeetool addEntryToKVM" "--mapName mockOBBRRegister --entryName jwks --entryValue \"$MOCKREGISTER_JWK\" 1> /dev/null | echo Added entry for jwks"
# set_cred "apigeetool addEntryToKVM" "--mapName mockOBBRRegister --entryName privateKey --entryValue \"$MOCKREGISTER_PRIVATE_KEY\"  1> /dev/null | echo Added entry for private key"

echo "--->"  Creating KVM mockOBBRClient...
set_cred "apigeetool createKVMmap" "--mapName mockOBBRClient --encrypted"
echo "--->"  Adding entries to mockADRClient...
MOCKCLIENT_JWKS=`cat ./OBBRTestApp.jwks`
MOCKCLIENT_PRIVATE_KEY=`cat ./OBBRTestApp_rsa_private.pem`
set_cred "apigeetool addEntryToKVM" "--mapName mockOBBRClient --entryName jwks --entryValue \"$MOCKCLIENT_JWKS\"  1> /dev/null | echo Added entry for jwks"
set_cred "apigeetool addEntryToKVM" "--mapName mockOBBRClient --entryName privateKey --entryValue \"$MOCKCLIENT_PRIVATE_KEY\"   1> /dev/null | echo Added entry for private key"

# Create KVM that will hold Apigee credentials (necessary for dynamic client registration operations), Apigee Private key and JWKS (Necessary for issuing JWT Tokens)
echo "--->"  Creating KVM OBBRConfig...
set_cred "apigeetool createKVMmap" "--mapName OBBRConfig --encrypted"
echo "--->"  Adding entries to OBBRConfig...
set_cred "apigeetool addEntryToKVM" "--mapName OBBRConfig --entryName ApigeeAPI_user --entryValue \"$APIGEE_USER\""
set_cred "apigeetool addEntryToKVM" "--mapName OBBRConfig --entryName ApigeeAPI_password --entryValue \"$APIGEE_PASSWORD\" 1> /dev/null | echo Added entry for password"
OBBRREFIMPL_JWKS=`cat ./OBBRRefImpl.jwks`
OBBRREFIMPL_PRIVATE_KEY=`cat ./OBBRRefImpl_rsa_private.pem`
set_cred "apigeetool addEntryToKVM" "--mapName OBBRConfig --entryName JWTSignKeys_jwks --entryValue \"$OBBRREFIMPL_JWKS\"  1> /dev/null | echo Added entry for OBBR Ref Impl jwks"
set_cred "apigeetool addEntryToKVM" "--mapName OBBRConfig --entryName JWTSignKeys_privateKey --entryValue "$OBBRREFIMPL_PRIVATE_KEY"   1> /dev/null | echo Added entry for OBBR Ref Impl private key"
set_cred "apigeetool addEntryToKVM" "--mapName OBBRConfig --entryName ApigeeIDPCredentials_clientId --entryValue \"$OBBRREFIMPL_OIDC_CLIENT_ID\"  1> /dev/null | echo Added entry for OBBR Ref Impl credentials: client id in OIDC Provider"
set_cred "apigeetool addEntryToKVM" "--mapName OBBRConfig --entryName ApigeeIDPCredentials_clientSecret --entryValue "$OBBRREFIMPL_OIDC_CLIENT_SECRET"   1> /dev/null | echo Added entry for OBBR Ref Impl credentials: client secret in OIDC Provider"
