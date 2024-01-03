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


     status as (type text meta 
    [
        Documentation.FieldCaption = "Статус кампании:",
        Documentation.AllowedValues = { "Все", "Активные" }
    ]),
    

    delay as (type nullable text meta 
    [
        Documentation.FieldCaption = "Задержка между запросами статистики (сек):",
        Documentation.SampleValues = {"59"}
    ])


    )
    as table meta [
        Documentation.Name = "Забираем данные по рекламе WildBerries",
        Documentation.LongDescription =  "",
        Documentation.Examples = {[ ]}
    ];



WBreklama.Func =  (start as text, finish as text, status as text, delay as nullable text)=>
let
del = if delay = null then "59" else Text.Replace(delay, ".",","),
headers = [#"Authorization" = Extension.CurrentCredential()[Key]],

web = Web.Contents("https://advert-api.wb.ru", [IsRetry  = true, RelativePath = "adv/v1/promotion/count", Headers = headers, ManualStatusHandling = {404, 400}]),
result = Json.Document(web, 65001),
adverts = result[adverts],
#"Преобразовано в таблицу" = Table.FromList(adverts, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
#"Развернутый элемент Column1" = Table.ExpandRecordColumn(#"Преобразовано в таблицу", "Column1", {"type", "status", "count", "advert_list"}, {"type", "status", "count", "advert_list"}),
#"Развернутый элемент advert_list" = Table.ExpandListColumn(#"Развернутый элемент Column1", "advert_list"),
#"Развернутый элемент advert_list1" = Table.ExpandRecordColumn(#"Развернутый элемент advert_list", "advert_list", {"advertId", "changeTime"}, {"advertId", "changeTime"}),
#"Измененный тип" = Table.TransformColumnTypes(#"Развернутый элемент advert_list1",{{"status", Int64.Type}, {"advertId", Int64.Type}}),
#"Строки с примененным фильтром" = if status = "Активные" then Table.SelectRows(#"Измененный тип", each [status] = 9) else #"Измененный тип",
rename = Table.RenameColumns(#"Строки с примененным фильтром" , {{"advertId", "campaignId"}}),
delete = Table.SelectColumns(rename, {"campaignId"}),

step1 = Table.SelectRows(getAll(delete,0, del, start, finish), each [advertId] <> null and [campaignIds] <> null),
more1 = Table.TransformColumnTypes(Table.SelectColumns(Table.SelectRows(Table.Join(delete, "campaignId" , step1, "campaignIds", JoinKind.LeftOuter), each [campaignIds]=null), {"campaignId"}),{{"campaignId", Int64.Type}}),
step2 = Table.SelectRows(getAll(more1,10, del, start, finish), each [advertId] <> null and [campaignIds] <> null),
more2 = Table.TransformColumnTypes(Table.SelectColumns(Table.SelectRows(Table.Join(more1, "campaignId" , step2, "campaignIds", JoinKind.LeftOuter), each [campaignIds]=null), {"campaignId"}),{{"campaignId", Int64.Type}}),
step3 = Table.SelectRows(getAll(more2,20, del, start, finish), each [advertId] <> null and [campaignIds] <> null),

all = step1 & step2 & step3,
filt = Table.Join(delete, "campaignId" , all, "campaignIds", JoinKind.LeftOuter)

in filt;



dateFunc = (dat)=>
        if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
        else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
        else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
        else dat;



getData = (body)=>
let
headers=[#"Authorization" = Extension.CurrentCredential()[Key]],
jsondata = Json.FromValue( body),
web =  Web.Contents("https://advert-api.wb.ru", [RelativePath = "adv/v2/fullstats", Content = jsondata, Headers = headers, ManualStatusHandling = {404, 400}]), 
result = Json.Document(web)
in result;


getNames = (campaign_list)=>
let
headers=[#"Authorization" = Extension.CurrentCredential()[Key]],
jsondata = Json.FromValue(campaign_list),
web = Web.Contents("https://advert-api.wb.ru", [RelativePath = "adv/v1/promotion/adverts", Content = jsondata, Headers = headers, ManualStatusHandling = {404, 400}]), 
result = Json.Document(web),
 #"Преобразовано в таблицу1" = Table.FromList(result, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
#"Развернутый элемент Column2" = Table.ExpandRecordColumn(#"Преобразовано в таблицу1", "Column1", {"endTime", "createTime", "changeTime", "startTime", "name", "params", "dailyBudget", "advertId", "status", "type"}, {"endTime", "createTime", "changeTime", "startTime", "name", "params", "dailyBudget", "advertId", "status", "type"}),
#"Измененный тип1" = Table.TransformColumnTypes(#"Развернутый элемент Column2",{{"advertId", Int64.Type}})
in #"Измененный тип1";


getAll = (tbl, pause, del as text, start as text, finish as text)=>
let 
    count = Table.RowCount(tbl),
    pau = if count = 0 then 0 else pause,
    maindel = if pause = 0 then del else pau,
    index = Table.AddIndexColumn(tbl, "Индекс", 0, 1, Int64.Type),
    delenie = Table.AddColumn(index, "Запрос", each Number.IntegerDivide([Индекс], 50), Int64.Type),
    delete2 = Table.RemoveColumns(delenie,{"Индекс"}),
    group = Table.Group(delete2, {"Запрос"}, {{"Кампании", each _[campaignId]}}),
    addBody = Table.AddColumn(group, "Тело", each List.Transform([Кампании], each [id = _, interval = [begin = dateFunc(start), end = dateFunc(finish)]])),
    addNames = Table.AddColumn(addBody, "campaign", each getNames([Кампании])),
    addData =  Table.AddColumn(addNames, "data", each if [Запрос]=0 then Function.InvokeAfter(()=> getData([Тело]), #duration(0,0,0,Number.From(pau)))  else 
    Function.InvokeAfter(()=> getData([Тело]), #duration(0,0,0,Number.From(maindel)))   ),
    delete3 = Table.RemoveColumns(addData,{"Запрос", "Кампании", "Тело"}),
    expNames = Table.ExpandTableColumn(Table.SelectColumns(delete3,{"campaign"}), "campaign", 
	{"endTime", "createTime", "changeTime", "startTime", "name", "params", "dailyBudget", "advertId", "status", "type"}, 
	{"endTime", "createTime", "changeTime", "startTime", "name", "params", "dailyBudget", "campaignIds", "status", "type"}),
    expData = Table.ExpandRecordColumn(Table.ExpandListColumn(Table.SelectColumns(delete3,{"data"}), "data"), "data", 
	{"interval", "views", "clicks", "ctr", "cpc", "sum", "atbs", "orders", "cr", "shks", "sum_price", "days", "advertId"}, 
	{"interval", "views", "clicks", "ctr", "cpc", "sum", "atbs", "orders", "cr", "shks", "sum_price", "days", "advertId"}),
    join = Table.Join(expData, "advertId" , expNames, "campaignIds" , JoinKind.FullOuter),
    chtype = Table.TransformColumnTypes(join,{{"campaignIds", Int64.Type}}),
    res =  if count = 0 then #table({"interval", "views", "clicks", "ctr", "cpc", "sum", "atbs", "orders", "cr", "shks", "sum_price", "days", "advertId", 
        "endTime", "createTime", "changeTime", "startTime", "name", "params", "dailyBudget", "campaignIds", "status", "type"},  {}) else chtype
in res;




WBreklama = [
    TestConnection = (dataSourcePath) => 
        {"WBreklama.Data", 
        Json.Document(dataSourcePath)[start], 
        Json.Document(dataSourcePath)[finish],
        Json.Document(dataSourcePath)[status],
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
