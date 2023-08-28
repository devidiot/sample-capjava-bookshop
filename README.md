# 프로젝트 생성 및 구성

CAP Node.js인 sample-cap-bookshop과 동일하게 CAP Java로 프로젝트를 생성 한 후 HANA Cloud, XSUAA, AppRouter등을 추가하고 로컬 개발 환경 및 CF Deploy까지 실행하는 Example 소스

```
cds init sample-capjava-bookshop --add java --java:mvn groupId=devidiot,artifactId=sample-capjava-bookshop,package=devidiot.sample

cd sample-capjava-bookshop
```

CAP Java의 경우 cds add 명령을 통해 sample 대신 tiny-sample만 추가가 가능함
```
cds add tiny-sample
```
tiny-sample은 role에 따른 구성이 없으므로 추가 후 ./srv/cat-service.cds를 아래와 같이 수정함
```
using my.bookshop as my from '../db/data-model';

service CatalogService @(path: '/browse') {
    @readonly entity Books as projection on my.Books;
}

service AdminService @(path: '/admin', requires: 'admin'){
    @readonly entity Books as projection on my.Books;
}
```

나머지 hana, xsuaa, approuter, mta 등을 추가함

```
cds add hana
cds add xsuaa
cds add approuter
cds add mta
```

## XSUAA 구성

xs-security.json 파일에 'xsappname', 'tenant-mode'와 OAuth 설정 'oauth2-configuration'을 추가함

아래는 xs-security.json의 전체이다.
```{
  "xsappname": "sample-capjava-bookshop",
  "tenant-mode": "dedicated",
  "scopes": [
    {
      "name": "$XSAPPNAME.admin",
      "description": "admin"
    }
  ],
  "attributes": [],
  "role-templates": [
    {
      "name": "admin",
      "description": "generated",
      "scope-references": [
        "$XSAPPNAME.admin"
      ],
      "attribute-references": []
    }
  ],
  "oauth2-configuration": {
    "redirect-uris": [
      "https://*.cfapps.us10-001.hana.ondemand.com/**"
    ]
  }
}
```
OAuth 설정 중 redirect-uris는 배포된 application의 URL Endpoint의 주소 패턴을 넣는다. 

위 URI는 BTP Trial에 sample-capjava-bookshop을 배포 했을 때의 URL 패턴이며, 배포대상 BTP가 Tenant에 따라 다를 수 있다.


## AppRouter 구성

app/xs-app.json 파일에 'authenticationMethod', 'authenticationType'을 지정함
authenticationMethod는 아래 route로 지정하고, authenticationType은 xsuaa로 지정함

아래는 xs-app.json의 전체이다.

```
{
  "welcomeFile": "app/index.html",
  "authenticationMethod": "route",
  "routes": [
    {
      "source": "^/app/(.*)$",
      "target": "$1",
      "localDir": ".",
      "cacheControl": "no-cache, no-store, must-revalidate",
      "authenticationType": "xsuaa"
    },
    {
      "source": "^/appconfig/",
      "localDir": ".",
      "cacheControl": "no-cache, no-store, must-revalidate",
      "authenticationType": "xsuaa"
    },
    {
      "source": "^/(.*)$",
      "target": "$1",
      "destination": "srv-api",
      "csrfProtection": true,
      "authenticationType": "xsuaa"
    }
  ]
}
```
authenticationType을 none으로 지정할 경우 해당 라우팅은 인증하지 않아도 서비스된다. 예를들어 "source": "^/app/(.*)$" 에 authenticationType을 none으로 할 경우 로그인 없이도 화면은 열린다.

welcomeFile로 지정한 app/index.html을 생성하여 아래와 같이 작성함
```
<HTML>
    <body>
        <ul>
            <li>
                <a href="/odata/v4/browse/Books">/odata/v4/browse/Books</a>
            </li>
            <li>
                <a href="/odata/v4/admin/Books">/odata/v4/admin/Books</a>
            </li>
        </ul>
    </body>
</HTML>
```

신규 CAP Java 프로젝트를 생성한 후 여기까지 따라한 후 아래 글에 따라 배포하고 실행한다.

<br/> <br/> <br/> <br/> 

# 배포 및 실행
사전에 cf에 login 해야한다. **아래 링크 참조**

https://help.sap.com/docs/btp/sap-business-technology-platform/log-on-to-cloud-foundry-environment-using-cloud-foundry-command-line-interface

<br/> 

## DB Deploy to HANA Cloud

DB Deploy를 위해 .cdsrc.json에 hana.deploy-format=hdbtable을 추가한다.

**최신의 HANA Cloud(DB)는 더이상 .hdbcds 배포를 지원하지 않는다. hdbtable/hdbview 배포를 사용해야 하므로 이 구성을 추가한해야 한다.**

```
{
    "hana": {
        "deploy-format": "hdbtable"
    }
}
```


## BTP Cloud Foundry에 배포

CF에 sample-capjava-bookshop을 빌드 및 배포한다.

```
mbt build
cf deploy ./mta_archives/sample-capjava-bookshop_1.0.0.mtar 
```

## Service Key 생성 (XSUAA & HDI)

배포 후 XSUAA Service와 HDI Container Service의 Service Key를 생성한다.
```
cf create-service-key sample-capjava-bookshop-auth sample-capjava-bookshop-auth-key
cf create-service-key sample-capjava-bookshop-db sample-capjava-bookshop-db-key
```

혹은 mta.yaml에 XSUAA 및 HDI Container 서비스에 key를 생성하는 설정을 아래와 같이 추가 햐여 배포시 자동으로 service key를 생성할 수 있다.
```
resources:
  - name: sample-capjava-bookshop-db
    type: com.sap.xs.hdi-container
    parameters:
      service: hana
      service-plan: hdi-shared
      service-keys:
        - name: sample-capjava-bookshop-db-key
  - name: sample-capjava-bookshop-auth
    type: org.cloudfoundry.managed-service
    parameters:
      service: xsuaa
      service-plan: application
      path: ./xs-security.json
      config:
        xsappname: sample-capjava-bookshop-${org}-${space}
        tenant-mode: dedicated
      service-keys:
        - name: sample-capjava-bookshop-auth-key
```


## 실행
BTP Cockpit에서 CF에 배포된 Application 'sample-capjava-bookshop'을 선택 후 Application Routes URL을 클릭하여 실행한다.
admin 권한은 없으므로 /browse/Books 만 실행 가능하며, /admin/Books는 "Not authorized to send event 'READ' to 'AdminService'" 오류가 발생한다.

admin 권한은 BTP Cockpit의 Subaccount에서 적절한 이름의 Role Collection을 신규 추가한 후 이 Role Collection에 배포 후 생성된 'sample-capjava-bookshop'의 admin Role 및 User를 추가하면 된다.
**물론 로그오프 후 재 로그인 해야 Role이 적용된다.**



<br/> <br/> <br/> <br/> 

# Hybrid Profile을 이용한 로컬 구동 

위 구성은 결과적으로 CDS Backend 서비스와 AppRouter를 통한 Frontend 서비스가 각각 구동되어 서비스되는 시나리오다.
이를 위해 Backend 및 Frontend가 모두 CF의 HDI Container와 XSUAA 서비스를 모두 바인드 하여 BTP의 DB 및 Role Collection을 통해 데이터 및 사용권한을 취득한다. 

<br/> 

## CF와 Binding

CF에 배포된 HDI Container 서비스와 XSUAA 서비스에 로컬 개발환경을 연결하여 개발이 가능하도록 한다.
Hybrid 라는 이름의 profile을 구성하여 이를 통해 로컬 서비스를 구동한다.

아래 두 명령을 실행하여 HDI Container와 XSUAA 서비스를 바인드한다. 
```
cds bind -2 sample-capjava-bookshop-db
cds bind -2 sample-capjava-bookshop-auth
```
실행후엔 hybrid provile로 구동 시 CF와 연결하여 구동하는데 필요한 바인드 정보가 .cdsrc-private.json 파일에 작성된다.

## Destination 설정

또한 Frontend인 Fiori Application이 Backend 서비스를 호출 하려면 로컬 환경에도 역시 Destination을 구성 해야한다. 

CF에 배포된 서비스의 경우 MTA를 통해 destionation 이름 srv-api 가 구성된다. (mta.yaml 참조)

로컬 서비스의 경우 app/default-env.json 파일을 통해 Destination을 구성한다.
app/default-env.json 파일이 없다면 아래와 같이 직접 파일을 생성하여 구성 할 수 있다.

```
{
  "destinations": [
    {
      "name": "srv-api",
      "url": "http://localhost:8080",
      "forwardAuthToken": true
    }
  ]
}
```

## 실행

위 2개의 cds bind 명령을 실행하면 프로젝트 Root 폴더에 .cdsrc-private.json 파일이 생성된다. 
로컬에서 서비스 구동시 이를 활용하여 CF 서비스에 바인딩한다.
아래 명령으로 SpringBoot을 구동한다. 
```
cds bind --exec -- mvn spring-boot:run
```

기본 포트번호 8080로 실행한 후에 모든 CDS Service는 Unauthorized가 된다. XSUAA를 활성화 했기 때문이며 AppRouter를 통해 XSUAA를 이용해야 정상으로 데이터에 접근이 가능하다.

아래 명령으로 AppRouter 서비스를 구동한다. 
```
cds bind --exec -- npm start --prefix app
```

AppRouter의 기본 포트는 5000 번이나 이 포트가 이미 로컬에서 사용중이라면 Port를 변경해야한다.
app/package.json 파일의 start script에 --port 옵션으로 5002을 추가한다.
```
{
    "destinations": [
        {
            "name": "srv-api",
            "url": "http://localhost:8080",
            "forwardAuthToken": true
        }
    ],
    "PORT": 5002
}
```

**참고로 이 소스는 AppRouter가 5001 포트로 구동하도록 구성되어 있다.**


## OAuth login callback URI 추가 구성

로컬 환경 또한 OAuth 구성으로 login/callback URL 패턴을 추가해야한다.
xs-security.json 파일에 OAuth 설정 'oauth2-configuration'의 redirect-uris에 BAS 또는 VSCode를 사용할 경우의 AppRouter URL 패턴을 추가한다.

```
{
  "oauth2-configuration": {
    "redirect-uris": [
      "https://*.cfapps.us10-001.hana.ondemand.com/**",
      "https://*.applicationstudio.cloud.sap/**",
      "http://localhost:*/**"
    ]
  }
}
```

**xs-security.json을 수정 한 후 이를 반영하기 위해 'sample-capjava-bookshop'을 재 배포해야한다. hybrid profile을 구성하여 CF에 바인딩 하여 구동하는 방식이므로 CF에 수정된 xs-security.json이 포함된 'sample-capjava-bookshop'이 update되어야 한다.**

redirect-ruls에 http 프로토콜은 오직 localhost인 경우만 가능하며 127.0.0.1은 허용되지 않는다.

localhost의 경우 5000번 포트가 아닐 수 있으므로 포트를 `*`로 처리하여 배포한다.