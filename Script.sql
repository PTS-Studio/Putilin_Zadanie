USE MASTER
GO

CREATE DATABASE Putilin4
GO

USE Putilin4
GO

----Создание таблиц для хранения инфы

----Сотрудники
CREATE TABLE employees (
    employee_id INT PRIMARY KEY IDENTITY(1,1),
    full_name NVARCHAR(100),
    department NVARCHAR(50),
    position NVARCHAR(50),
    hire_date DATE,
    is_active BIT DEFAULT 1,
    manager_id INT NULL
);
GO

----Паспортные данные
CREATE TABLE passport_data (
    passport_id INT PRIMARY KEY IDENTITY(1,1),
    employee_id INT UNIQUE,
    passport_no NVARCHAR(20),
    issued_by NVARCHAR(100),
    issue_date DATE,
    birth_date DATE,
    CONSTRAINT FK_passport_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);
GO


----Данные зарплат
CREATE TABLE salary_log (
    log_id INT PRIMARY KEY IDENTITY(1,1),
    employee_id INT,
    amount DECIMAL(10,2),
    calc_date DATE,
    access_user NVARCHAR(100),
    CONSTRAINT FK_salary_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);
GO


----Аудит
CREATE TABLE audit_access (
    audit_id INT PRIMARY KEY IDENTITY(1,1),
    access_time DATETIME DEFAULT GETDATE(),
    table_name NVARCHAR(50),
    record_id INT,
    user_name NVARCHAR(100),
    action_type NVARCHAR(20)
);
GO

CREATE TABLE archive_emp (
    archive_id INT PRIMARY KEY IDENTITY(1,1),
    employee_id INT,
    full_name NVARCHAR(100),
    delete_date DATE DEFAULT GETDATE(),
    destroy_date DATE DEFAULT DATEADD(DAY, 30, GETDATE())
);
GO

CREATE TABLE analytics_mapping (
    mapping_id INT PRIMARY KEY IDENTITY(1,1),
    pseudo_uuid UNIQUEIDENTIFIER DEFAULT NEWID(),
    department_agg NVARCHAR(50),
    salary_range NVARCHAR(20),
    hire_year INT
);
GO

CREATE TABLE user_roles (
    user_id INT PRIMARY KEY IDENTITY(1,1),
    username NVARCHAR(100),
    role_name NVARCHAR(50),
    employee_id INT NULL
);
GO

CREATE TABLE [session_context] (
    [session_id] INT PRIMARY KEY IDENTITY(1,1),
    username NVARCHAR(100),
    role_name NVARCHAR(50),
    employee_id INT NULL
);
GO

----Представление для рядового сотрудника
CREATE VIEW v_employee_self
AS
SELECT e.*
FROM employees e
WHERE e.employee_id = ISNULL((SELECT employee_id FROM session_context WHERE username = SUSER_NAME()), -1);
GO

----Представление для руководителя
CREATE VIEW v_manager_team
AS
SELECT e.*
FROM employees e
WHERE e.manager_id = (SELECT employee_id FROM session_context WHERE username = SUSER_NAME());
GO

----Представление для HR
CREATE VIEW v_hr_all
AS
SELECT * FROM employees;
GO

----Представление для HR
CREATE VIEW v_hr_passport
AS
SELECT * FROM passport_data;
GO

----Представление для бухгалтера
CREATE VIEW v_accountant_employees
AS
SELECT * FROM employees;
GO

----Представление для бухгалтера
CREATE VIEW v_accountant_passport
AS
SELECT employee_id, passport_no, birth_date FROM passport_data;
GO

----Представление для аналитика
CREATE VIEW v_analyst_mapping
AS
SELECT * FROM analytics_mapping;
GO

-- Триггер аудита для passport_data (INSERT)
CREATE TRIGGER trg_audit_passport_insert
ON passport_data
AFTER INSERT
AS
BEGIN
    INSERT INTO audit_access (table_name, record_id, user_name, action_type, access_time)
    SELECT 'passport_data', employee_id, SUSER_NAME(), 'INSERT', GETDATE()
    FROM inserted;
END;
GO

-- Триггер аудита для passport_data (UPDATE)
CREATE TRIGGER trg_audit_passport_update
ON passport_data
AFTER UPDATE
AS
BEGIN
    INSERT INTO audit_access (table_name, record_id, user_name, action_type, access_time)
    SELECT 'passport_data', employee_id, SUSER_NAME(), 'UPDATE', GETDATE()
    FROM inserted;
END;
GO

-- Триггер аудита для passport_data (DELETE)
CREATE TRIGGER trg_audit_passport_delete
ON passport_data
AFTER DELETE
AS
BEGIN
    INSERT INTO audit_access (table_name, record_id, user_name, action_type, access_time)
    SELECT 'passport_data', employee_id, SUSER_NAME(), 'DELETE', GETDATE()
    FROM deleted;
END;
GO

----триггер на удаление сотрудника
CREATE TRIGGER trg_employee_archive
ON employees
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO archive_emp (employee_id, full_name, delete_date, destroy_date)
    SELECT employee_id, full_name, GETDATE(), DATEADD(DAY, 30, GETDATE())
    FROM deleted;
    
    DELETE FROM salary_log WHERE employee_id IN (SELECT employee_id FROM deleted);
    DELETE FROM passport_data WHERE employee_id IN (SELECT employee_id FROM deleted);
    DELETE FROM employees WHERE employee_id IN (SELECT employee_id FROM deleted);
    
    INSERT INTO audit_access (table_name, record_id, user_name, action_type, access_time)
    SELECT 'employees', employee_id, SUSER_NAME(), 'ARCHIVE_DELETE', GETDATE()
    FROM deleted;
END;
GO

----Хранимая процедура для администратора
CREATE PROCEDURE sp_get_dismissed_with_destroy
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        employee_id,
        full_name,
        delete_date,
        destroy_date,
        DATEDIFF(DAY, GETDATE(), destroy_date) AS days_left_until_destroy
    FROM archive_emp
    WHERE destroy_date > GETDATE();
    
    INSERT INTO audit_access (table_name, record_id, user_name, action_type, access_time)
    SELECT 'archive_emp', employee_id, SUSER_NAME(), 'AUTO_DELETE', GETDATE()
    FROM archive_emp
    WHERE destroy_date <= GETDATE();
    
    DELETE FROM archive_emp WHERE destroy_date <= GETDATE();
    
    PRINT 'Устаревшие записи удалены, аудит зафиксирован.';
END;
GO

----Процедура установки контекста пользователя
CREATE PROCEDURE sp_set_user_context
    @username NVARCHAR(100),
    @role_name NVARCHAR(50),
    @employee_id INT = NULL
AS
BEGIN
    DELETE FROM session_context WHERE username = @username;
    INSERT INTO session_context (username, role_name, employee_id)
    VALUES (@username, @role_name, @employee_id);
END;
GO

----Вставка
INSERT INTO employees (full_name, department, position, hire_date, is_active, manager_id) VALUES
(N'Иванов Иван', N'IT', N'разработчик', '2020-01-10', 1, NULL),
(N'Петрова Мария', N'Бухгалтерия', N'гл. бухгалтер', '2019-05-20', 1, 1),
(N'Сидоров Алексей', N'HR', N'HR-специалист', '2021-03-15', 0, NULL);
GO

INSERT INTO passport_data (employee_id, passport_no, issued_by, issue_date, birth_date) VALUES
(1, N'1234 123456', N'ОВД Москвы', '2015-03-10', N'1990-05-12'),
(2, N'1234 654321', N'ОВД СПб', '2016-07-22', N'1985-08-25');
GO

INSERT INTO user_roles (username, role_name, employee_id) VALUES
(N'ivanov', N'Employee', 1),
(N'petrova', N'Accountant', 2),
(N'sidorov', N'HR_Specialist', 3),
(N'analyst', N'HR_Analyst', NULL),
(N'admin', N'DB_Admin', NULL);
GO

-- Установка контекста для HR-специалиста
EXEC sp_set_user_context N'sidorov', N'HR_Specialist', 3;

SELECT * FROM v_hr_all;
SELECT * FROM v_hr_passport;

----Установка контекста для рядового сотрудника
EXEC sp_set_user_context N'ivanov', N'Employee', 1;

----Сотрудник видит только свои данные через представление
SELECT * FROM v_employee_self;

----Проверка архивного триггера
DELETE FROM employees WHERE employee_id = 3;

----Проверка процедуры администратора
EXEC sp_get_dismissed_with_destroy;

----ролевая модель доступа
SELECT 'Рядовой сотрудник' AS role, 'SELECT только свои данные' AS rights, 'v_employee_self' AS view_name
UNION ALL
SELECT 'Руководитель отдела', 'SELECT данные подчинённых', 'v_manager_team'
UNION ALL
SELECT 'HR-специалист (Кадры)', 'SELECT/INSERT/UPDATE/DELETE все', 'v_hr_all, v_hr_passport'
UNION ALL
SELECT 'Бухгалтер', 'SELECT employees + чтение passport для зарплаты', 'v_accountant_employees, v_accountant_passport'
UNION ALL
SELECT 'HR-аналитик', 'SELECT только обезличенные данные', 'v_analyst_mapping'
UNION ALL
SELECT 'Администратор БД', 'ALL PRIVILEGES (структурные изменения)', 'прямой доступ к таблицам';
GO