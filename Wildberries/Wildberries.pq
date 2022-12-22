// This file contains your Data Connector logic
section Wildberries;

[DataSource.Kind="Wildberries", Publish="Wildberries.Publish"]
shared Wildberries.Data = Value.ReplaceType(Wildberries.Func, FuncType);

FuncType = type function (
      
    reportType  as (type text meta 
    [
        Documentation.FieldCaption = "Выберите тип отчёта:",
        Documentation.SampleValues = {"Продажи"},
        Documentation.AllowedValues = { "Остатки", "Поставки", "Заказы", "Продажи","Реализация" }
    ]),
     
    dateFrom as (type text meta 
    [
        Documentation.FieldCaption = "Дата начала:",
        Documentation.SampleValues = {"2022-02-28"}
    ]),
    
    periodDays as (type nullable text meta 
    [
        Documentation.FieldCaption = "Период сбора (N дней):",
        Documentation.SampleValues = {"30"}
    ]),
    delay as (type nullable text meta 
    [
        Documentation.FieldCaption = "Задержка при выполнении запросов:",
        Documentation.SampleValues = {"10"}
    ])

    )
    as table meta [
        Documentation.Name = "Забираем данные из WildBerries",
        Documentation.LongDescription =  "",
        Documentation.Examples = {
        [
            
        ]
        }
    ];



Wildberries.Func =    (reportType as text, dateFrom as text, periodDays as nullable text, delay as nullable text)=>

let 
    perriod = if periodDays=null then "30" else periodDays,
    dela = if delay=null then "10" else delay,
    start = dateFunc(dateFrom),
    apiKey = Extension.CurrentCredential()[Key],
    
    dateTable=
    let
        Источник = List.Dates(Date.From(start), (Number.From(Date.From(DateTime.LocalNow()) - Date.From(start))+1)/Number.From(perriod),#duration(Number.From(perriod),0,0,0)),
        #"Преобразовано в таблицу" = Table.FromList(Источник, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Переименованные столбцы" = Table.RenameColumns(#"Преобразовано в таблицу",{{"Column1", "Дата1"}}),
        #"Измененный тип" = Table.TransformColumnTypes(#"Переименованные столбцы",{{"Дата1", type date}}),
        #"Добавлен пользовательский объект" = Table.AddColumn(#"Измененный тип", "Дата2", each if [Дата1]+#duration(Number.From(perriod)-1,0,0,0)> Date.From(DateTime.LocalNow()) then Date.From(DateTime.LocalNow())  else [Дата1]+#duration(Number.From(perriod)-1,0,0,0)),
        #"Измененный тип1" = Table.TransformColumnTypes(#"Добавлен пользовательский объект",{{"Дата2", type date}})
    in
        #"Измененный тип1",


    orders = 
    let 
        dates = dateTable,
        data1 = Table.AddColumn(dates, "data1c", each getOrdersFunc(apiKey, [Дата1], [Дата2], dela)),
        data2= Table.AddColumn(data1, "data2c", each if [data1c]=null then getOrdersFunc(apiKey, [Дата1], [Дата2], dela) else [data1c]), 
        data3= Table.AddColumn(data2, "data", each if [data2c]=null then getOrdersFunc(apiKey, [Дата1], [Дата2], dela) else [data2c]), 
        addStatus =  Table.AddColumn(data3, "Статус сбора данных", each if [data]=null then "Данные не получены" else if Table.RowCount([data])>50000 then "Уменьшите N в периоде сбора" else "Всё ОК"),
        delete = Table.RemoveColumns(addStatus,{"data1c", "data2c"})

    in
        delete,


    sales = 
    let 
        dates = dateTable,
        data1 = Table.AddColumn(dates, "data1c", each getSalesFunc(apiKey, [Дата1], [Дата2], dela)),
        data2= Table.AddColumn(data1, "data2c", each if [data1c]=null then getSalesFunc(apiKey, [Дата1], [Дата2], dela) else [data1c]), 
        data3= Table.AddColumn(data2, "data", each if [data2c]=null then getSalesFunc(apiKey, [Дата1], [Дата2], dela) else [data2c]), 
        addStatus =  Table.AddColumn(data3, "Статус сбора данных", each if [data]=null then "Данные не получены" else if Table.RowCount([data])>50000 then "Уменьшите N в периоде сбора" else "Всё ОК"),
        delete = Table.RemoveColumns(addStatus,{"data1c", "data2c"})

    in
        delete,


    realized = 
    let 
        dates = dateTable,
        data1 = Table.AddColumn(dates, "data1c", each reportDetailByPeriod(apiKey, [Дата1], [Дата2], dela)),
        data2= Table.AddColumn(data1, "data2c", each if [data1c]=null then reportDetailByPeriod(apiKey, [Дата1], [Дата2], dela) else [data1c]), 
        data3= Table.AddColumn(data2, "data", each if [data2c]=null then reportDetailByPeriod(apiKey, [Дата1], [Дата2], dela) else [data2c]), 
        addStatus =  Table.AddColumn(data3, "Статус сбора данных", each if [data]=null then "Данные не получены" else if Table.RowCount([data])>50000 then "Уменьшите N в периоде сбора" else "Всё ОК"),
        delete = Table.RemoveColumns(addStatus,{"data1c", "data2c"})

    in
        delete,

    ostatki=
    let
        web=Json.Document(Web.Contents("https://statistics-api.wildberries.ru/", [RelativePath = "api/v1/supplier/stocks", Headers=[#"Authorization"= apiKey, #"Content-Type"="application/json"], Query=[#"dateFrom"=start]])),
        columns = List.Distinct(List.Combine(List.Transform(web, each Record.FieldNames(_)))),
        #"Преобразовано в таблицу" = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Развернутый элемент Column1" = Table.ExpandRecordColumn(#"Преобразовано в таблицу", "Column1", columns, columns),
        #"Извлеченный текст перед разделителем" = Table.TransformColumns(#"Развернутый элемент Column1", {{"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}}),
        #"Измененный тип" = Table.TransformColumnTypes(#"Извлеченный текст перед разделителем",{{"lastChangeDate", type date}, {"Discount", type number}}),
        #"Разделенный столбец" = Table.TransformColumns(#"Измененный тип", {{"Discount", each _ / 100, type number}}),
        #"Измененный тип1" = Table.TransformColumnTypes(#"Разделенный столбец",{{"Discount", Percentage.Type}})
    in
        #"Измененный тип1",


    postavki = 
    let
        web=Json.Document(Web.Contents("https://statistics-api.wildberries.ru/", [RelativePath = "api/v1/supplier/incomes",  Headers=[#"Authorization"= apiKey, #"Content-Type"="application/json"], Query=[ #"dateFrom"=start]])),
        columns = List.Distinct(List.Combine(List.Transform(web, each Record.FieldNames(_)))),
        #"Преобразовано в таблицу" = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Развернутый элемент Column1" = Table.ExpandRecordColumn(#"Преобразовано в таблицу", "Column1", columns, columns),
        #"Измененный тип" = Table.TransformColumnTypes(#"Развернутый элемент Column1",{{"date", type text}, {"lastChangeDate", type text}, {"dateClose", type text}}),
        split = Table.TransformColumns(#"Измененный тип", {{"date", each Text.BeforeDelimiter(_, "T"), type text},{"dateClose", each Text.BeforeDelimiter(_, "T"), type text},{"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}}),
        #"Измененный тип1" = Table.TransformColumnTypes(split,{{"lastChangeDate", type date}, {"date", type date}, {"dateClose", type date}})
    in
        #"Измененный тип1",

    
    
    report = 
    if reportType = "Остатки" then ostatki else
    if reportType = "Поставки" then postavki else
    if reportType = "Заказы" then orders else
    if reportType = "Продажи" then sales else
    if reportType = "Реализация" then realized else 
    "Отчёт не выбран",
    
    reporterror = try report

in 
    try reporterror[Error] otherwise reporterror[Value];



dateFunc = (dat)=>
        if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
        else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
        else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
        else dat;


getOrdersFunc = (apiKey as text, dateFr as date, dateTo as date, delay as text)=> 
    let
        dateFrom = Date.ToText(dateFr,"yyyy-MM-dd"),
        web = Function.InvokeAfter(()=>Json.Document(Web.Contents("https://statistics-api.wildberries.ru/api/v1/supplier/orders", [Headers=[#"Authorization"= apiKey, #"Content-Type"="application/json"], Query=[#"dateFrom"=dateFrom]])), #duration(0,0,0,Number.From(delay))),
        columnList = List.Distinct(Record.FieldNames(web{0})),
        recordsFromList = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        tableFromRecords = Table.ExpandRecordColumn(recordsFromList, "Column1", columnList, columnList),
        dubli = Table.Distinct(tableFromRecords, columnList),
        textType = Table.TransformColumns(dubli, {{"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}, {"date", each Text.BeforeDelimiter(_, "T"), type text},{"cancel_dt", each Text.BeforeDelimiter(_, "T"), type text}}),
        dateType = Table.TransformColumnTypes(textType,{{"date", type date}, {"lastChangeDate", type date}, {"cancel_dt", type date}}),
        final = Table.SelectRows(dateType, each ([lastChangeDate] <= dateTo))
        
    in
        try final otherwise null;
    
    
getSalesFunc = (apiKey as text, dateFr as date, dateTo as date, delay as text)=> 
    let
        dateFrom = Date.ToText(dateFr,"yyyy-MM-dd"),
        web = Function.InvokeAfter(()=>Json.Document(Web.Contents("https://statistics-api.wildberries.ru/api/v1/supplier/sales", [Headers=[#"Authorization"= apiKey, #"Content-Type"="application/json"], Query=[#"dateFrom"=dateFrom]])), #duration(0,0,0,Number.From(delay))),
        columnList =  List.Distinct(Record.FieldNames(web{0})),
        recordsFromList = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        tableFromRecords = Table.ExpandRecordColumn(recordsFromList, "Column1", columnList, columnList), 
        dubli = Table.Distinct(tableFromRecords, columnList),
        textType = Table.TransformColumns(dubli, {{"date", each Text.BeforeDelimiter(_, "T"), type text}, {"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}}),
        saleIds = Table.TransformColumnTypes(textType,{{"saleID", type text}}),
        status = Table.AddColumn(saleIds, "Статус", each Text.Start([saleID], 1), type text),
        #"Замененное значение" = Table.ReplaceValue(status,"S","Продажа",Replacer.ReplaceText,{"Статус"}),
        #"Замененное значение1" = Table.ReplaceValue(#"Замененное значение","R","Возврат",Replacer.ReplaceText,{"Статус"}),
        #"Замененное значение2" = Table.ReplaceValue(#"Замененное значение1","A","Сторно продаж",Replacer.ReplaceText,{"Статус"}),
        #"Замененное значение3" = Table.ReplaceValue(#"Замененное значение2","B","Сторно возврата",Replacer.ReplaceText,{"Статус"}),
        #"Замененное значение4" = Table.ReplaceValue(#"Замененное значение3","D","Доплата",Replacer.ReplaceText,{"Статус"}),
        dateType = Table.TransformColumnTypes(#"Замененное значение4",{{"date", type date}, {"lastChangeDate", type date}}),        
        final = Table.SelectRows(dateType, each ([lastChangeDate] <= dateTo))
        
    in
        try final otherwise null;



reportDetailByPeriod = (apiKey as text, dateFr as date, dateTo as date, delay as text)=> 
    let
        dateFrom = Date.ToText(dateFr,"yyyy-MM-dd"),
        dateToText = Date.ToText(dateTo,"yyyy-MM-dd"),
        web = Function.InvokeAfter(()=>Json.Document(Web.Contents("https://statistics-api.wildberries.ru/api/v1/supplier/reportDetailByPeriod", 
        [Headers=[#"Authorization"= apiKey, #"Content-Type"="application/json"], Query=[#"dateFrom"=dateFrom, #"dateto"=dateToText]])), #duration(0,0,0,Number.From(delay))),
        columnList =  List.Distinct(Record.FieldNames(web{0})),
        recordsFromList = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        tableFromRecords = Table.ExpandRecordColumn(recordsFromList, "Column1", columnList, columnList),   
        dubli = Table.Distinct(tableFromRecords, columnList),
        textType = Table.TransformColumns(dubli, {{"order_dt", each Text.BeforeDelimiter(_, "T"), type text}, {"sale_dt", each Text.BeforeDelimiter(_, "T"), type text}, {"rr_dt", each Text.BeforeDelimiter(_, "T"), type text}}),
        dateType = Table.TransformColumnTypes(textType,{{"order_dt", type date}, {"rr_dt", type date}, {"sale_dt", type date}}),       
        final = dateType 
       
    in
        try final otherwise null;



Wildberries = [
    TestConnection = (dataSourcePath) => 
        { "Wildberries.Data", 
        Json.Document(dataSourcePath)[reportType], 
        Json.Document(dataSourcePath)[dateFrom], 
        Json.Document(dataSourcePath)[periodDays]?,
        Json.Document(dataSourcePath)[delay]?
        },
    Authentication = [
        
         Key = []
   
    ],
    Label = "Wildberries Connection"
];



Wildberries.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { "Wildberries Connector", "Wildberries Help" },
    LearnMoreUrl = "",
    SourceImage = Wildberries.Icons,
    SourceTypeImage = Wildberries.Icons
];



Wildberries.Icons = [
    Icon16 = { Extension.Contents("Wildberries16.png"), Extension.Contents("Wildberries20.png"), Extension.Contents("Wildberries24.png"), Extension.Contents("Wildberries32.png") },
    Icon32 = { Extension.Contents("Wildberries32.png"), Extension.Contents("Wildberries40.png"), Extension.Contents("Wildberries48.png"), Extension.Contents("Wildberries64.png") }
];
