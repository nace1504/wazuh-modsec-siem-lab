-- DVWA Database Initialization Script
CREATE DATABASE IF NOT EXISTS dvwa;
USE dvwa;

-- Users table
DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `user_id` int(6) NOT NULL AUTO_INCREMENT,
  `first_name` varchar(15) DEFAULT NULL,
  `last_name` varchar(15) DEFAULT NULL,
  `user` varchar(15) DEFAULT NULL,
  `password` varchar(32) DEFAULT NULL,
  `avatar` varchar(70) DEFAULT NULL,
  `last_login` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `failed_login` int(3) DEFAULT '0',
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed admin and test accounts (passwords MD5)
-- admin / password (5f4dcc3b5aa765d61d8327deb882cf99)
-- gordonb / abc123 (e99a18c428cb38d5f260853678922e03)
-- 1337 / charlie (5d41402abc4b2a76b9719d911017c592)
-- pablo / letmein (7815696ecbf1c96e6894b779456d330e)
-- smith / password (5f4dcc3b5aa765d61d8327deb882cf99)
INSERT INTO `users` (`user_id`, `first_name`, `last_name`, `user`, `password`, `avatar`, `last_login`, `failed_login`) VALUES
(1, 'admin', 'admin', 'admin', '5f4dcc3b5aa765d61d8327deb882cf99', 'admin.jpg', NOW(), 0),
(2, 'Gordon', 'Brown', 'gordonb', 'e99a18c428cb38d5f260853678922e03', 'gordonb.jpg', NOW(), 0),
(3, 'Hack', 'Me', '1337', '5d41402abc4b2a76b9719d911017c592', '1337.jpg', NOW(), 0),
(4, 'Pablo', 'Picasso', 'pablo', '7815696ecbf1c96e6894b779456d330e', 'pablo.jpg', NOW(), 0),
(5, 'Bob', 'Smith', 'smith', '5f4dcc3b5aa765d61d8327deb882cf99', 'smith.jpg', NOW(), 0);

-- Guestbook table for Stored XSS demonstrations
DROP TABLE IF EXISTS `guestbook`;
CREATE TABLE `guestbook` (
  `comment_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `comment` varchar(300) DEFAULT NULL,
  `name` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`comment_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `guestbook` (`comment_id`, `comment`, `name`) VALUES
(1, 'This is a test comment.', 'admin');

