create procedure syn.usp_ImportFileCustomerSeasonal
	@ID_Record int
AS
set nocount on
begin
	declare 
		@RowCount int = (select count(*) from syn.SA_CustomerSeasonal)
		,@ErrorMessage varchar(8000)

	-- Проверка на корректность загрузки                                                           
	if not exists (                                                     
		select 1                                                                                    
		from syn.ImportFile as f                                                                   
		where f.ID = @ID_Record                                                                   
			and f.FlagLoaded = cast(1 as bit)                                                     
	)
	begin                                                                                      
		set @ErrorMessage = 'Ошибка при загрузке файла, проверьте корректность данных'
		raiserror(@ErrorMessage, 3, 1)
		
		return                                                                           
	end

	-- Чтение из слоя временных данных                                                                 
	select
		c.ID as cstm                                                 
		,cst.ID as csst
		,s.ID as ss
		,cast(cs.DateBegin as date) as dtb                                 
		,cast(cs.DateEnd as date) as dte                                          
		,c_dist.ID as cd                                      
		,cast(isnull(cs.FlagActive, 0) as bit) as fla                          
	into #CustomerSeasonal
	from syn.SA_CustomerSeasonal as cs                                                  
		join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
			and c.ID_mapping_DataSource = 1                                               
		join dbo.Season as s on s.Name = cs.Season
		join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor
			and c_dist.ID_mapping_DataSource = 1                                                
		join syn.CustomerSystemType as cst on cs.CustomerSystemType = cst.Name
	where try_cast(cs.DateBegin as date) is not null
		and try_cast(cs.DateEnd as date) is not null
		and try_cast(isnull(cs.FlagActive, 0) as bit) is not null

	/*
		Определяем некорректные записи.               
		Добавляем причину, по которой запись считается некорректной
	*/
	select
		cs.*
		,case
			when c.ID is null 
				then 'UID клиента отсутствует в справочнике "Клиент"'                   
			when c_dist.ID is null 
				then 'UID дистрибьютора отсутствует в справочнике "Клиент"'
			when s.ID is null 
				then 'Сезон отсутствует в справочнике "Сезон"'
			when cst.ID is null 
				then 'Тип клиента отсутствует в справочнике "Тип клиента"'
			when try_cast(cs.DateBegin as date) is null 
				then 'Невозможно определить Дату начала'              
			when try_cast(cs.DateEnd as date) is null 
				then 'Невозможно определить Дату окончания'
			when try_cast(isnull(cs.FlagActive, 0) as bit) is null 
				then 'Невозможно определить Активность'
		end as Reason                                                                                          
	into #BadInsertedRows
	from syn.SA_CustomerSeasonal as cs
	left join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
		and c.ID_mapping_DataSource = 1                                                                                                
	left join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor and c_dist.ID_mapping_DataSource = 1
	left join dbo.Season as s on s.Name = cs.Season
	left join syn.CustomerSystemType as cst on cst.Name = cs.CustomerSystemType
	where c.ID is null
		or c_dist.ID is null
		or s.ID is null
		or cst.ID is null
		or try_cast(cs.DateBegin as date) is null
		or try_cast(cs.DateEnd as date) is null
		or try_cast(isnull(cs.FlagActive, 0) as bit) is null

	-- Обработка данных из файла
	merge syn.CustomerSeasonal as cs                                                         
	using (
		select
			cs_temp.ID_dbo_Customer
			,cs_temp.ID_CustomerSystemType                                                   
			,cs_temp.ID_Season
			,cs_temp.DateBegin
			,cs_temp.DateEnd
			,cs_temp.ID_dbo_CustomerDistributor
			,cs_temp.FlagActive
		from #CustomerSeasonal as cs_temp                                                   
	) as s on s.ID_dbo_Customer = cs.ID_dbo_Customer            
		and s.ID_Season = cs.ID_Season
		and s.DateBegin = cs.DateBegin
	when matched and t.ID_CustomerSystemType <> s.ID_CustomerSystemType then 
		update
		set csst = s.ID_CustomerSystemType
			,dte = s.DateEnd                                                             
			,cd = s.ID_dbo_CustomerDistributor
			,fla = s.FlagActive
	when not matched then                                                                   
		insert (cstm, csst, ss, dtb, dte, cd, fla)
		values (s.ID_dbo_Customer, s.ID_CustomerSystemType, s.ID_Season, s.DateBegin, s.DateEnd, s.ID_dbo_CustomerDistributor, s.FlagActive);

	-- Информационное сообщение
	begin
		select @ErrorMessage = concat('Обработано строк: ', @RowCount)
		raiserror(@ErrorMessage, 1, 1)

		-- Формирование таблицы для отчетности                                                                               
		select top 100
			bir.Season as 'Сезон'
			,bir.UID_DS_Customer as 'UID Клиента'
			,bir.Customer as 'Клиент'
			,bir.CustomerSystemType as 'Тип клиента'
			,bir.UID_DS_CustomerDistributor as 'UID Дистрибьютора'
			,bir.CustomerDistributor as 'Дистрибьютор'
			,isnull(format(try_cast(bir.DateBegin as date), 'dd.MM.yyyy', 'ru-RU'), bir.DateBegin) as 'Дата начала'
			,isnull(format(try_cast(bir.DateEnd as date), 'dd.MM.yyyy', 'ru-RU'), bir.DateEnd) as 'Дата окончания'
			,bir.FlagActive as 'Активность'
			,bir.Reason as 'Причина'
		from #BadInsertedRows as bir

		return
	end
end
