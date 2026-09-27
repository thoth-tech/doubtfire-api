class ApplicationRecord < ActiveRecord::Base
  include LogHelper
  self.abstract_class = true

  def self.current_read_prefix
    connection = self.connection
    @current_read_prefixes ||= {}
    key = [connection.adapter_name, connection.database_version.to_s]
    unless @current_read_prefixes.key?(key)
      supported = connection.respond_to?(:mariadb?) && connection.mariadb? &&
                  connection.select_rows("SHOW VARIABLES LIKE 'innodb_snapshot_isolation'").any?
      @current_read_prefixes[key] = supported ? 'SET STATEMENT innodb_snapshot_isolation=OFF FOR ' : ''
    end
    @current_read_prefixes.fetch(key)
  end
  private_class_method :current_read_prefix

  def self.current_rows(relation)
    # MariaDB snapshot isolation rejects a locking read of newer committed rows.
    # Delivery admission explicitly needs current rows for its locks. The statement
    # override leaves the surrounding transaction/session configuration intact;
    # older MariaDB and MySQL use their ordinary locking-read behavior.
    sql = "#{current_read_prefix}#{relation.lock.to_sql}"
    uncached { find_by_sql(sql) }
  end

  def self.with_current_row_access
    return yield if current_read_prefix.empty?

    connection = self.connection
    previous = connection.select_value('SELECT @@SESSION.innodb_snapshot_isolation').to_i
    return yield if previous.zero?

    # Foreign-key checks during INSERT also acquire locks. Limit this MariaDB
    # compatibility setting to notification reservation and always restore it
    # before the caller's surrounding workflow resumes. Locks and foreign-key
    # constraints remain enabled; ordinary MySQL needs no override.
    begin
      connection.execute('SET SESSION innodb_snapshot_isolation = OFF')
      yield
    ensure
      connection.execute('SET SESSION innodb_snapshot_isolation = ON')
    end
  end
end
