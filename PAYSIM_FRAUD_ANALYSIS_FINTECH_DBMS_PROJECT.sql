use PAYSIM;

select top 10* from paysimdataset;

create table transactions (
    transactionid int identity(1,1) primary key,
    step int not null,
    type nvarchar(30) not null,
    amount decimal(18,2) not null,
    nameorig nvarchar(50) not null,
    oldbalanceorg decimal(18,2) null,
    newbalanceorig decimal(18,2) null,
    namedest nvarchar(50) not null,
    oldbalancedest decimal(18,2) null,
    newbalancedest decimal(18,2) null,
    isfraud bit not null,
    isflaggedfraud bit not null
);

update transactions
set nameorig = trim(nameorig),
    namedest = trim(namedest);

create table customers (
    customerid int identity(1,1) primary key,
    customername nvarchar(50) unique
);

create table transactiontypes (
    typeid int identity(1,1) primary key,
    typename nvarchar(30) unique
);



insert into transactions
(step, type, amount, nameorig, oldbalanceorg, newbalanceorig,
 namedest, oldbalancedest, newbalancedest, isfraud, isflaggedfraud)
select
step, type, amount, nameorig, oldbalanceorg, newbalanceorig,
namedest, oldbalancedest, newbalancedest, isfraud, isflaggedfraud
from paysimdataset;

insert into transactiontypes (typename)
select distinct type
from paysimdataset;

insert into customers (customername)
select customername from (
    select distinct nameorig as customername from transactions
    union
    select distinct namedest from transactions
) as allcustomers;

alter table transactions add typeid int null;
alter table transactions add origcustomerid int null;
alter table transactions add destcustomerid int null;
go

update t
set typeid = tt.typeid,
    origcustomerid = co.customerid,
    destcustomerid = cd.customerid
from transactions t
join transactiontypes tt on tt.typename = t.type
join customers co on co.customername = t.nameorig
join customers cd on cd.customername = t.namedest;
go

alter table transactions alter column typeid int not null;
alter table transactions alter column origcustomerid int not null;
alter table transactions alter column destcustomerid int not null;
go

alter table transactions
add constraint fk_trx_type foreign key (typeid)
references transactiontypes(typeid);

alter table transactions
add constraint fk_trx_orig foreign key (origcustomerid)
references customers(customerid);

alter table transactions
add constraint fk_trx_dest foreign key (destcustomerid)
references customers(customerid);
go














--Analysis 1:
--This monitors fraud activity in real-time by tracking fraud volume per day (step) and per customer.

create view fraudbystep as
select 
    step,
    count(*) as totaltransactions,
    sum(case when isfraud = 1 then 1 else 0 end) as fraudcount,
    (sum(case when isfraud = 1 then 1 else 0 end) * 100.0 / count(*)) as fraudpercentage
from transactions
group by step;
go

create procedure fraudwindow
    @startstep int,
    @endstep int
as
begin

    select *
    from fraudbystep
    where step between @startstep and @endstep
    order by fraudpercentage desc;

end
go

select * 
from fraudbystep
order by step desc;

exec fraudwindow 1, 24;

--Decision
--Bank should increase monitoring and fraud detection rules during time periods where fraud percentage spikes.

--Cross Functional Benefits
--Improves fraud detection, supports risk management, enables real-time IT alerts, and enhances compliance reporting.


--Analysis 2:
--Identifies large transactions that may indicate money laundering or suspicious activity.

create function fn_largetransactions(@multiplier decimal(5,2))
returns table
as
return
(
    select 
        transactionid,
        step,
        type,
        amount,
        nameorig,
        isfraud
    from transactions
    where amount > @multiplier * (
        select avg(amount)
        from transactions)
);
go

create procedure highvaluespenders
    @threshold decimal(18,2)
as
begin

    select 
        nameorig,
        count(*) as highvaluecount,
        sum(amount) as totalexposure
    from transactions
    where amount > @threshold
    group by nameorig
    order by totalexposure desc;

end
go

select * 
from fn_largetransactions(3.0);

exec highvaluespenders 50000000;

--Decision
--Apply additional verification for high-value transactions and flag repeated high spenders.

--Cross Functional Benefits
--Strengthens AML controls, reduces financial risk, improves customer authentication, and supports fraud analytics teams.

--Analysis 3:
--Identifies customer spending patterns and abnormal behavior.

create view vw_customerbehavior
as
select 
    c.customername as SenderID,
    count(*) as totaltransactions,
    avg(t.amount) as avgamount,
    max(t.amount) as maxamount,
    sum(t.amount) as totalspend
from transactions t
join customers c on c.customerid = t.origcustomerid
where c.customername like 'c%'
group by c.customername;
go

select * from vw_customerbehavior order by totalspend desc;

select SenderID, avgamount
from vw_customerbehavior
where avgamount > (select avg(amount) * 2 from transactions)
order by avgamount desc;

--Decision
--Flag customers with unusually high average transaction value for monitoring.

--Cross Functional Benefits:
--Enables customer profiling, improves fraud detection, supports marketing segmentation, and enhances risk scoring models.

--Analysis 4:
--Evaluates which transaction types dominate system usage and fraud risk.

create view vw_typeperformance
as
select 
    tt.typename as type,
    count(*) as totaltransactions,
    sum(t.amount) as totalvolume,
    sum(case when t.isfraud = 1 then 1 else 0 end) as fraudcount,
    (sum(case when t.isfraud = 1 then 1 else 0 end) * 100.0 / count(*)) as fraudrate
from transactions t
join transactiontypes tt
on tt.typeid = t.typeid
group by tt.typename;
go

select * from vw_typeperformance order by fraudrate desc;

--Decision
--Strengthen fraud detection in transaction types with highest fraud occurrence.

--Cross Functional Benefit
--Cross Functional Benefits: Improves product design, enhances fraud controls, supports business strategy decisions, and optimizes IT system performance.

--Analysis 5:
--Provides system-wide fraud ratio for governance and decision-making

create view vw_fraudoverview as
select 
    count(*) as totaltransactions,
    sum(case when isfraud = 1 then 1 else 0 end) as fraudtransactions,
    (sum(case when isfraud = 1 then 1 else 0 end) * 100.0 / count(*)) as fraudpercentage
from transactions;
go

-- shows customers involved in fraud transactions

create view vw_topfraudsters as
select 
    c.customername as nameorig,
    count(*) as fraudcases
from transactions t
join customers c
on c.customerid = t.origcustomerid
where t.isfraud = 1
group by c.customername;
go

select * from vw_fraudoverview;

select top 10 * from vw_topfraudsters order by fraudcases desc;

--Decision 
--Bank should continuously monitor system-wide fraud percentage and generate alerts when risk thresholds are exceeded.

--Cross Functional Benefits
--Supports executive decision-making, strengthens audit compliance, improves fraud governance, and enhances security operations.

