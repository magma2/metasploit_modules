#
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
#
# MD5 lookup
#
# Author: hasherezade (http://hasherezade.net)
# Source: https://github.com/hasherezade/metasploit_modules/blob/master/md5_lookup.rb
#

require 'msf/core'

class Metasploit3 < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient

  def initialize(info={})
    super(update_info(info,
      'Name'           => "Md5 lookup",
      'Description'    => %q{
          This auxiliary module attempts to reverse provided MD5 hashes by lookup in online databases.
      },
      'License'        => MSF_LICENSE,
      'Author'         =>
        [
          'hAsh (http://hasherezade.net)' # Metasploit module
        ]
    ))

    register_options(
    [
      OptPath.new('PATH', [true, 'File with md5 hashes']),
    ])
    register_advanced_options(
    [
      OptPort.new('RPORT',[true, 'Port of the lookup service', 80]),
      OptString.new('RHOST',[true, 'Host used for lookup', 'md5cracker.org']),
      OptString.new('TARGETURI', [true, 'URI of the lookup service', '/api/api.cracker.php']),
      OptString.new('DATABASES',[true, 'Comma separated list of MD5 online databases',
          "authsecu, i337.net, md5.my-addr.com, md5.net, md5crack, md5cracker.org, md5decryption.com, md5online.net, md5pass, netmd5crack, tmto"
          ]),
    ])
    deregister_options('VHOST', 'Proxies')
  end

# utils
  def read_file()
    path = datastore['PATH']
    print_status("Trying to read file: #{path}")

    if not File::exist?(path)
      print_error("No such file")
      return nil
    elsif not File::file?(path)
      print_error("Invalid path")
      return nil
    end
    hash_counter = 0
    hashes = Set.new
    my_file = File::new(path, mode="r")
    my_file.each {|line| 
      hash = fetchMd5(line)
      if hash
         hashes << hash
         hash_counter += 1
      end
      }
    my_file.close
    print_status("Found hashes: #{hash_counter}, unique: #{hashes.length}")
    return hashes
  end

  def get_string_between(my_string, start_at, end_at)
    my_string = "#{my_string}"

    ini = my_string.index(start_at)
    return nil if ini == 0

    ini += start_at.length
    length = my_string.index(end_at, ini).to_i - ini
    my_string[ini,length]
  end

  def fetchMd5(my_string)
    if my_string  =~ /([0-9a-fA-F]{32})/
      return $1
    end
    return nil
  end

  def md5search(hash, database)
    hash = fetchMd5(hash)
    if not hash
      return nil
    end

    port = datastore['RPORT']
    old_ssl = autoenable_ssl(port)
    res = send_request_cgi({
        'method' => 'GET',
        'uri'    => normalize_uri(target_uri.path),
        'vars_get'   => { "database" => database, "hash" => hash }
    })
    datastore['SSL'] = old_ssl

    if not res or res.code != 200 or res.body.empty?
      print_error("#{url}, db: #{database} - returned invalid response")
      return nil
    end
    # "status":true, "result":"123",
    if res.body =~ /\>404 Not Found\</
       return nil
    end

    if res.body =~ /true/
      tag1 = "result\":\""
      tag2 = "\","
      password = get_string_between(res.body, tag1, tag2)
      return password
    end
    return nil
  end

  def fetch_db_names(names_string)
    values = names_string.split(",").map(&:strip)
    if values 
      return values.to_set()
    end
    return nil
  end


  def md5crack(hash, md5_databases)
    for db in md5_databases
      pass = md5search(hash, db)
      if pass
        return pass
      end
    end
    return nil
  end

  def crack_hashes(hashes, md5_databases)
    return nil if not hashes
    cracked = 0
    for chunk in hashes
      pass = md5crack(chunk, md5_databases)
      if pass
        print_good("#{chunk} : #{pass}")
        cracked += 1
      else
        print_error("#{chunk}")
      end
    end
    print_status("Found passwords: #{cracked} out of #{hashes.length}")
  end

  def autoenable_ssl(port)
    old_ssl = datastore['SSL']
      if (port == URI::HTTP::DEFAULT_PORT)
        datastore['SSL'] = false
      elsif (port == URI::HTTPS::DEFAULT_PORT)
        datastore['SSL'] = true
      end
      return old_ssl
  end

# MSF API:

  def run
    hashes = read_file()
    if not hashes or hashes.length() == 0
      print_error("No hashes supplied")
      return nil
    end
    md5_dbs = fetch_db_names(datastore['DATABASES'])
    if not md5_dbs or md5_dbs.length() == 0
      print_error("No databases supplied!")
      return nil
    end
    if datastore['VERBOSE']
      print_status("Loaded: #{md5_dbs.length()} databases")
    end
    print_status("Attempting to reverse hashes...")
    crack_hashes(hashes, md5_dbs)
  end

end

