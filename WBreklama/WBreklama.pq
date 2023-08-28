// This file contains your Data Connector logic
section WBreklama;


[DataSource.Kind="WBreklama", Publish="WBreklama.Publish"]
shared WBreklama.Data = Value.ReplaceType(WBreklama.Func, FuncType);

FuncType = type function (
          

    start as (type text meta 
    [
        Documentation.FieldCaption = "Дата начала:",
        Documentation.SampleValues = {"2023-09-28"}
    ]),
    
    finish as (type text meta 
    [
        Documentation.FieldCaption = "Дата окончания:",
        Documentation.SampleValues = {"yesterday"}
    ])

    )
    as table meta [
        Documentation.Name = "Забираем данные по рекламе WildBerries",
        Documentation.LongDescription =  "",
        Documentation.Examples = {
        [
            
        ]
        }
    ];



WBreklama.Func =    (start as text, finish as text)=>
let
headers = [#"Authorization" = Extension.CurrentCredential()[Key]],
web = Web.Contents("https://advert-api.wb.ru", [IsRetry  = true, RelativePath = "adv/v0/adverts", Headers = headers, ManualStatusHandling = {404, 400}]),
result = Json.Document(web, 65001),
totable = Table.FromList(result, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
expand = Table.ExpandRecordColumn(totable, "Column1", {"advertId", "name", "type", "status"}, {"advertId", "name", "type", "status"}),
chtype = Table.TransformColumnTypes(expand,{{"advertId", type text}, {"name", type text}, {"type", type text}, {"status", type text}}),
#"Добавлен пользовательский объект" = Table.AddColumn(chtype, "data", each getData([advertId], dateFunc(start), dateFunc(finish) )),
#"Переименованные столбцы" = Table.RenameColumns(#"Добавлен пользовательский объект",{{"advertId", "campaign_id"}, {"name","campaign_name"}}),
listexp = List.Select(List.Accumulate( #"Переименованные столбцы"[data], {}, (st,cr) => List.Distinct(st & Record.FieldNames(cr))), each _<>"advertId" and _<>"begin" and _<>"end"),
expall = Table.ExpandRecordColumn(#"Переименованные столбцы", "data", listexp, listexp)
in  expall;



dateFunc = (dat)=>
        if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
        else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
        else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
        else dat;


getData = (campaign_id,  start, finish)=>
let
headers=[#"Authorization" = Extension.CurrentCredential()[Key]],
querydata = [#"id" = campaign_id, #"begin" = start, #"end" = finish],
web = Web.Contents("https://advert-api.wb.ru", [RelativePath = "adv/v1/fullstat", Headers = headers, ManualStatusHandling = {404, 400}, Query = querydata]),
result = Json.Document(web)
in result;


WBreklama = [
    TestConnection = (dataSourcePath) => 
        { "WBreklama.Data", 
        Json.Document(dataSourcePath)[start], 
        Json.Document(dataSourcePath)[finish]
        },
    Authentication = [
        
         Key = []
   
    ],
    Label = "WBreklama Connection"
];



WBreklama.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { "WBreklama Connector", "WBreklama Help" },
    LearnMoreUrl = "",
    SourceImage = WBreklama.Icons,
    SourceTypeImage = WBreklama.Icons
];



WBreklama.Icons = [
    Icon16 = { Extension.Contents("WBreklama16.png"), Extension.Contents("WBreklama20.png"), Extension.Contents("WBreklama24.png"), Extension.Contents("WBreklama32.png") },
    Icon32 = { Extension.Contents("WBreklama32.png"), Extension.Contents("WBreklama40.png"), Extension.Contents("WBreklama48.png"), Extension.Contents("WBreklama64.png") }
];
