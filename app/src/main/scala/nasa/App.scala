package nasa

import org.apache.spark.sql.{SparkSession, DataFrame}
import org.apache.spark.sql.functions.{to_date, sum, count, min, when, broadcast}

/***
  Convert CSV of NASA website requests to the following aggregations by date:
    - active IPs (# of hosts that showed up 10+ times in a day)
    - average page views (# page views/# hosts)
    - total bytes returned
    - average bytes returned (# bytes/# requests)
    - percent requests successful (# requests that returned 200s/# requests)
    - acquisition (# distinct hosts that showed up for first time ever on given date)
    - retention (# distinct hosts that showed up on given date but have requested from website previously)
  ***/
object App {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession
      .builder()
      .appName("Aggregate Nasa")
      .getOrCreate();
    import spark.implicits._

    // Get the csv file + write it to Parquet
    spark.read.option("header", "true")
      .option("inferSchema", "true")
      .option("delimiter", " ")
      .csv("s3://nasa-hannah/nasa_aug95.csv")
      .drop($"request")
      .withColumn("date", to_date($"datetime"))
      .drop($"datetime")
      .write.mode("overwrite").parquet("nasa.parquet")

    // Take the original dataframe
    // - convert status column to a 1/0 whether or not it was successful
    // - Group by date, requesting host returning count of pages requested, total number of successful requests, and bytes amount
    var df = spark.read.parquet("nasa.parquet")
      .repartition(48, $"date", $"requesting_host")
      .withColumn("successful", when($"status" >= 200 && $"status" <= 299, 1).otherwise(0))
      .groupBy($"date", $"requesting_host")
      .agg(count($"requesting_host").as("pages_per_host_per_date"),
      sum($"successful").as("successful"),
      sum($"response_size").as("response_size"))
      .cache()

    // Take the dataframe grouped by request host + date and get the count of distinct hosts that were new for a given date
    val hostFirstDateDF = df
      .repartition(48, $"requesting_host")
      .groupBy($"requesting_host".as("host")).agg(min($"date").as("first_date"))
      .groupBy($"first_date").agg(count($"first_date").as("acquisition"))

    // Take the original dataframe and
    // - Create column that shows 1/0 "active ips" (whether or not a host had more than 10 page requests in a given day)
    // - Group by date getting count of distinct hosts, count of active IPs, average page views, total bytes, average bytes,
    //   and percent successful
    // - Join to the df that has count of new hosts on a given day, and grab the acquisition (# new hosts) and the retention (number of returning hosts)
    df.withColumn("active", when($"pages_per_host_per_date" > 10, 1).otherwise(0))
      .groupBy($"date")
      .agg(count($"pages_per_host_per_date").as("distinct_hosts"),
      sum($"active").as("active_ips"),
      (sum($"pages_per_host_per_date")/count($"pages_per_host_per_date")).as("average_page_views"),
      sum($"response_size").as("total_bytes"),
      (sum($"response_size")/sum($"pages_per_host_per_date")).as("average_bytes"),
      (sum($"successful")/sum($"pages_per_host_per_date")).as("percent_successful"))
      .join(broadcast(hostFirstDateDF), $"date" === $"first_date", "left")
      .select($"date", $"active_ips", $"average_page_views", $"total_bytes", $"average_bytes", $"percent_successful", $"acquisition", ($"distinct_hosts"-$"acquisition").as("retention"))
      .write.mode("overwrite").option("header", "true").option("delimiter", " ").csv("s3://nasaforhannah/result.csv")
  }
}
