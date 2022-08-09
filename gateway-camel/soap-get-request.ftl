<#ftl encoding="utf-8">
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:hel="http://www.example.com/hello">
   <soapenv:Header/>
   <soapenv:Body>
      <hel:sayHello>
         <name>${headers.name}</name>
      </hel:sayHello>
   </soapenv:Body>
</soapenv:Envelope>