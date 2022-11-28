
#check if powershell version is 7.0 or higher and if not, warn the user and exit
if($PSVersionTable.PSVersion.Major -lt 7)
{
    Write-Host "This script requires PowerShell 7.0 or higher. Please update your PowerShell version and try again." -ForegroundColor Red
    exit
}

#check if Az module version 9 or higher is installed and if not, warn the user and install it or upgrade it
if((Get-Module -Name Az -ListAvailable).Version.Major -lt 9)
{
    Write-Host "The Az module is not installed. Installing it now..." -ForegroundColor Yellow
    Install-Module -Name Az -Scope CurrentUser -Force
}

$budgetName="provderBudget"


# Set the CSV file to be created in your script location
$MyPath=$PSScriptRoot
$MyCSVPath=$MyPath+"\MySecureScores.csv"# Get all tenants accessible by the current identity
$MyAzPath=$MyPath+"\tenants.txt"
# Connect with the identity for which you would like to check Secure Score
# Only subscriptions with appropriate permissions will list a score.
Connect-AzAccount

#$MyAzTenants=Get-AzTenant
$MyAzTenants=Get-Content -Path $MyAzPath

foreach($MyAzTenant in $MyAzTenants){
    Write-Output "Checking tenant: $MyAzTenant" # Get all subscriptions within the selected tenant
    $MyAzSubscriptions = Get-AzSubscription -TenantId $MyAzTenant | Where-Object -Property State -NE 'Disabled'

    foreach($MyAzSubscription in $MyAzSubscriptions){
        Write-Output "Checking subcription: $MyAzSubscription"
        Set-AzContext -Subscription $MyAzSubscription -Tenant $MyAzTenant # Get the Secure Score for each subscription$
        $check=@(Get-AzResourceProvider | Where-Object -Property ProviderNamespace -EQ 'Microsoft.Security' | Where-Object  -Property RegistrationState -EQ 'Registered').Count
        
        if($check -gt 0){
            $MyAzSecureScore = Get-AzSecuritySecureScore # Create an array containing the Secure Score data$
            $MyCSVRow= @( [pscustomobject]@{
                Date=(Get-Date).Date;
                TenantName=$MyAzTenant.Name;
                SubscriptionID=$MyAzSubscription.Id;
                SubscriptionName=$MyAzSubscription.Name;
                SecureScore= $MyAzSecureScore.Percentage;
                Weight = $MyAzSecureScore.Weight
            } )# Append the Secure Score to the CSV file$
            $MyCSVRow | Export-Csv $MyCSVPath -Append
        }
        else {
            Write-Output "Register Security on subcription: $MyAzSubscription"
            Register-AzResourceProvider  -ProviderNamespace 'Microsoft.Security'  
        }
        #Login Rest Api
        $accessToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
        $apiUrl="https://management.azure.com/subscriptions/"+$MyAzSubscription.Id+"/providers/Microsoft.Consumption/budgets?api-version=2021-10-01" 
        $checkBdg= ((Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken"} -Uri $apiUrl -ContentType 'application/json' -Method GET -Verbose).value| Where-Object -Property name -EQ $budgetName).Count
        if ($checkBdg -eq 0){
            #Create Budget
            $body= Get-Content -Raw -Path $MyPath"\budget.json"
           
            $apiUrl="https://management.azure.com/subscriptions/"+$MyAzSubscription.Id+"/providers/Microsoft.Consumption/budgets/"+ $budgetName  +"?api-version=2021-10-01"
            Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken"} -Uri $apiUrl -ContentType 'application/json' -Method PUT -Verbose -Body $body

        }

    }
}# You can extend the script with a foreach, cycling through all Secure Score controls for additional detail: Get-AzSecuritySecureScoreControl.


