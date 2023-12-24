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
    ]),

    delay as (type nullable text meta 
    [
        Documentation.FieldCaption = "Задержка между запросами (сек):",
        Documentation.SampleValues = {"0.3"}
    ])


    )
    as table meta [
        Documentation.Name = "Забираем данные по рекламе WildBerries",
        Documentation.LongDescription =  "",
        Documentation.Examples = {[ ]}
    ];



WBreklama.Func =  (start as text, finish as text, delay as nullable text)=>
let
del = if delay = null then "0,3" else Text.Replace(delay, ".",","),
headers = [#"Authorization" = Extension.CurrentCredential()[Key]],
web = Web.Contents("https://advert-api.wb.ru", [IsRetry  = true, RelativePath = "adv/v1/promotion/count", Headers = headers, ManualStatusHandling = {404, 400}]),
result = Json.Document(web, 65001),
adverts = result[adverts],
#"Преобразовано в таблицу" = Table.FromList(adverts, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
#"Развернутый элемент Column1" = Table.ExpandRecordColumn(#"Преобразовано в таблицу", "Column1", {"type", "status", "count", "advert_list"}, {"type", "status", "count", "advert_list"}),
#"Развернутый элемент advert_list" = Table.ExpandListColumn(#"Развернутый элемент Column1", "advert_list"),
#"Развернутый элемент advert_list1" = Table.ExpandRecordColumn(#"Развернутый элемент advert_list", "advert_list", {"advertId", "changeTime"}, {"advertId", "changeTime"}),
rename = Table.RenameColumns(#"Развернутый элемент advert_list1" ,{{"advertId", "campaignId"}}),
delete = Table.SelectColumns(rename, {"campaignId"}),
addData =  Table.AddColumn(delete, "data", each getData(Text.From([campaignId]), dateFunc(start), dateFunc(finish), del)),
addNames = Table.AddColumn(addData, "names", each getNames(Text.From([campaignId]),del)),
explist = Table.ExpandListColumn(addNames, "names"),
expand = Table.ExpandRecordColumn(explist, "names", Record.FieldNames(explist{0}[names]), Record.FieldNames(explist{0}[names])),
explist2 =  Table.ExpandListColumn(expand, "data"),
explist3 =  Table.ExpandListColumn(explist2, "params")
in  explist3;



dateFunc = (dat)=>
        if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
        else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
        else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
        else dat;


getData = (campaign_id as text, begin as text, end as text, del as text )=>
let
headers=[#"Authorization" = Extension.CurrentCredential()[Key]],
jsondata = Json.FromValue( {[#"id"= Number.From(campaign_id), #"interval"= [begin = begin, end = end]]}),
web =  Function.InvokeAfter(()=>  Web.Contents("https://advert-api.wb.ru", [RelativePath = "adv/v2/fullstats", Content = jsondata, Headers = headers, ManualStatusHandling = {404, 400}]), #duration(0,0,0,Number.From(del))),
result = Json.Document(web)
in result;


getNames = (campaign_id as text, del as text)=>
let
headers=[#"Authorization" = Extension.CurrentCredential()[Key]],
jsondata = Json.FromValue( {Number.From(campaign_id)}),
web =  Function.InvokeAfter(()=> Web.Contents("https://advert-api.wb.ru", [RelativePath = "adv/v1/promotion/adverts", Content = jsondata, Headers = headers, ManualStatusHandling = {404, 400}]), #duration(0,0,0,Number.From(del))),
result = Json.Document(web)
in result;


WBreklama = [
    TestConnection = (dataSourcePath) => 
        {"WBreklama.Data", 
        Json.Document(dataSourcePath)[start], 
        Json.Document(dataSourcePath)[finish],
        Json.Document(dataSourcePath)[delay]?
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
